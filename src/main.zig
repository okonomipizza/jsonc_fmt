const std = @import("std");
const Allocator = std.mem.Allocator;

const jsonpico = @import("jsonpico");
const JsonParser = jsonpico.JsonParser;
const JsonValue = jsonpico.JsonValue;

const clap = @import("clap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var stdout = std.fs.File.stdout();
    var stdout_writer = stdout.writerStreaming(&.{});
    var stderr = std.fs.File.stderr();
    var stderr_writer = stderr.writerStreaming(&.{});

    // CLI config
    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit.
        \\-v, --version         Output version information and exit.
    );
    var diag = clap.Diagnostic{};

    // Parse command-line args
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = a,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        const help_info =
        \\ USAGE
        \\   echo '{"key": "value"}' | jsonc_fmt
        \\ FLAGS
        \\   -h, --help     Show help
        \\   -v, --version  Show jsonc_fmt version
        ;
        return try stdout_writer.interface.writeAll(help_info);
    }
    if (res.args.version != 0) {
        const version_info =
        \\ jsonc_fmt v0.1.0
        \\ A JSON with Comments formatter written in Zig
        ;
        return try stdout_writer.interface.writeAll(version_info);
    }

    var stdin = std.fs.File.stdin();
    // Buffer to read input
    var buffer: [4096]u8 = undefined;
    var input = try std.ArrayList(u8).initCapacity(a, 4096);
    defer input.deinit(a);

    while (true) {
        const bytes_read = try stdin.read(buffer[0..]);
        if (bytes_read == 0) break;
        try input.appendSlice(a, buffer[0..bytes_read]);
    }

    var parser = JsonParser.init(a, input.items) catch |err| {
        try stderr_writer.interface.print("JSON Parser initialization error: {}\n", .{err});
        std.process.exit(1);
    };
    defer parser.deinit(a);

    var parsed = parser.parse(a) catch |err| {
        try stderr_writer.interface.print("Failed to parse JSON: {}\n", .{err});
        return;
    };
    defer parsed.deinit(a);

    var formatted_string = try std.ArrayList(u8).initCapacity(a, input.items.len);
    defer formatted_string.deinit(a);

    const writer = formatted_string.writer(a);

    var formatter = Formatter.init(a, input.items, parser.positions, parser.comment_ranges);
    defer formatter.deinit();

    formatter.format(a, parsed, writer) catch |err| {
        try stderr_writer.interface.print("Failed to format JSON: {}\n", .{err});
        return;
    };
    try writer.writeByte('\n');

    try stdout_writer.interface.writeAll(formatted_string.items);
}

const CommentType = enum {
    line, // // comment
    block, // /* comment */
};

const Comment = struct {
    type: CommentType,
    content: []const u8,
};

const FormatError = error{
    NoOffset,
    InvalidObject,
    OutOfMemory,
    InvalidComment,
};

const Formatter = struct {
    input: []const u8,
    position: usize,
    positions: jsonpico.PositionMap,
    comment_ranges: jsonpico.CommentRanges,
    used_comments: std.AutoHashMap(usize, bool),
    indent: usize, // indent levels
    indent_size: usize, // width of a indent

    pub fn init(a: Allocator, input: []const u8, positions: jsonpico.PositionMap, comment_ranges: jsonpico.CommentRanges) Formatter {
        return .{ .input = input, .position = 0, .positions = positions, .comment_ranges = comment_ranges, .used_comments = std.AutoHashMap(usize, bool).init(a),.indent = 0, .indent_size = 4 };
    }

    pub fn deinit(self: *Formatter) void {
        self.used_comments.deinit();
    }

    pub fn format(self: *Formatter, a: Allocator, v: JsonValue, w: anytype) FormatError!void {
        switch (v) {
            .null => {
                try v.Stringify(a, w);
            },
            .bool => {
                try v.Stringify(a, w);
            },
            .integer, .float => {
                try v.Stringify(a, w);
            },
            .string => {
                try w.print("\"{s}\"", .{v.string.value.items});
            },
            .array => {
                try v.Stringify(a, w);
            },
            .object => {
                try self.formatObject(a, v, w);
            },
        }
    }

    fn formatObject(self: *Formatter, a: Allocator, v: JsonValue, w: anytype) FormatError!void {
        if (v != .object) return FormatError.InvalidObject;

        try w.writeByte('{');
        try w.writeByte('\n');
        self.indent += 1;

        const obj = v.object.value;
        const key_count = obj.count();

        for (obj.keys(), 0..) |key, i| {
            const is_last = (i == key_count - 1);
            try self.writeIndent(w);

            // Get key
            var key_bytes = try std.ArrayList(u8).initCapacity(a, key.len);
            defer key_bytes.deinit(a);
            try key_bytes.writer(a).writeAll(key);

            // Get value
            const value: JsonValue = obj.get(key) orelse return FormatError.InvalidObject;

            // Write leading comment
            const leading_comment: ?Comment = try self.leadingComment(value);
            if (leading_comment) |c| {
                switch (c.type) {
                    .line => {
                        try w.print("// {s}\n", .{c.content});
                        try self.writeIndent(w);
                    },
                    .block => {
                        const com = try self.formatBlockComment(a, c.content);
                        try w.print("/* {s} */\n", .{com});
                        a.free(com);
                        try self.writeIndent(w);
                    },
                }
            }

            // Write key and value
            try w.print("\"{s}\": ", .{key_bytes.items});
            try self.format(a, value, w);

            if (!is_last) {
                try w.writeByte(',');
            }

            // Write trailing comment
            const trailing_comment: ?Comment = try self.trailingComment(value);
            if (trailing_comment) |c| {
                switch (c.type) {
                    .line => {
                        try w.print(" // {s}\n", .{c.content});
                    },
                    .block => {
                        try w.print(" /* {s} */\n", .{c.content});
                    },
                }
            } else {
                try newline(w);
            }
        }

        self.indent -= 1;
        try self.writeIndent(w);
        try w.writeByte('}');
    }

    fn leadingComment(self: *Formatter, v: JsonValue) FormatError!?Comment {
        const value_range = self.positions.get(v.getId()) orelse return FormatError.NoOffset;

        const lastline_range = self.getLastLineRange(value_range.start);
        if (lastline_range) |range| {
            const lastline = self.input[range.start .. range.end + 1];
            if (std.mem.indexOf(u8, lastline, "//")) |_| {
                return self.searchComment(range.start, range.end);
            }
            if (std.mem.indexOf(u8, lastline, "/*")) |_| {
                return self.searchComment(range.start, range.end);
            }
            // For multiple lines
            if (std.mem.indexOf(u8, lastline, "*/")) |_| {
                var i = range.start;
                while (i >= 0) {
                    const maybe_first_line_range = self.getLastLineRange(i).?;
                    const maybe_first_line = self.input[maybe_first_line_range.start .. maybe_first_line_range.end + 1];
                    if (std.mem.indexOf(u8, maybe_first_line, "/*")) |_| {
                        return self.searchComment(maybe_first_line_range.start, range.end);
                    }
                    i = maybe_first_line_range.start;
                    if (i > 0) i -= 1;
                }
                return self.searchComment(range.start, range.end);
            }
        }

        return null;
    }

    fn formatBlockComment(self: *Formatter, a: Allocator, comment: []const u8) FormatError![]const u8 {
        var result = try std.ArrayList(u8).initCapacity(a, comment.len);

        var i: usize = 0;
        while (i < comment.len) : (i += 1) {
            const char = comment[i];

            if (char == '\n') {
                try result.append(a, '\n');

                while (i + 1 < comment.len and (comment[i + 1] == ' ' or comment[i + 1] == '\t')) {
                    i += 1;
                }

                var remaining = self.indent * self.indent_size + 3; // +3 for "/* " prefix
                while (remaining > 0) : (remaining -= 1) {
                    try result.append(a, ' ');
                }
            } else {
                try result.append(a, char);
            }
        }
        return result.toOwnedSlice(a);
    }

    fn getLastLineRange(self: *Formatter, curr: usize) ?struct { start: usize, end: usize } {
        var lastline_start: usize = curr;
        var lastline_end: usize = curr;

        var i: usize = curr;
        var lastline_found = false;

        while (i >= 0) : (i -= 1) {
            if (self.input[i] == '\n') {
                if (!lastline_found) {
                    lastline_found = true;
                    lastline_end = i;
                    continue; // At end of last line
                } else {
                    lastline_start = i + 1;
                    break; // At start of last line
                }
            }
            if (i == 0) break;
        }

        if (lastline_start > lastline_end) lastline_start = 0;

        if (!lastline_found) return null; // There is no previous line

        if (lastline_start >= 0 and lastline_end < self.input.len) {
            return .{ .start = lastline_start, .end = lastline_end };
        }
        return null;
    }

    fn trailingComment(self: *Formatter, v: JsonValue) FormatError!?Comment {
        const value_range = self.positions.get(v.getId()) orelse return FormatError.NoOffset;
        const eol = blk: {
            var i: usize = value_range.end;
            while (i < self.input.len) : (i += 1) {
                if (self.input[i] == '\n') {
                    break :blk i;
                }
            }
            break :blk self.input.len - 1;
        };
        return try self.searchComment(value_range.end + 1, eol);
    }

    /// Returns if there is a comment between start and end
    fn searchComment(self: *Formatter, from: usize, until: usize) FormatError!?Comment {
        for (self.comment_ranges.items) |range| {
            if (range.start >= from and range.end <= until) {
                if (self.used_comments.get(range.start)) |_| {
                    continue;
                }

                const comment = try self.parseComment(range.start, range.end);

                try self.used_comments.put(range.start, true);

                return comment;
            }
        }
        return null;
    }

    /// Generate Comment from commet range
    fn parseComment(self: Formatter, start: usize, end: usize) FormatError!Comment {
        const comment_value = std.mem.trim(u8, self.input[start .. end + 1], " \t");
        var i = start;
        while (i >= 0) : (i -= 1) {
            const char = self.input[i];
            if (char == '/') {
                const prev = self.input[i - 1];
                if (prev == '/') {
                    return .{ .content = comment_value, .type = .line };
                }
            } else if (char == '*') {
                const prev = self.input[i - 1];
                if (prev == '/') {
                    return .{ .content = comment_value, .type = .block };
                }
            }
        }
        return error.InvalidComment;
    }

    fn getString(self: *Formatter) []const u8 {
        const start = self.position;
        var end = start;

        self.position += 1; // Next to start '"'

        while (self.position < self.input.len) : (self.position += 1) {
            const char = self.getChar(self.position) orelse break;
            if (char == '"') {
                end = self.position;
                self.position += 1; // Finish at next to last '"'
                break;
            }
        }

        return self.input[start .. end + 1];
    }

    fn writeIndent(self: *Formatter, writer: anytype) !void {
        const total_space = self.indent * self.indent_size;
        try writeCharN(writer, ' ', total_space);
    }

    fn writeCharN(writer: anytype, char: u8, n: usize) !void {
        var buffer: [256]u8 = undefined;
        @memset(&buffer, char);

        var remaining = n;
        while (remaining > 0) {
            const chunk_size = @min(remaining, buffer.len);
            try writer.writeAll(buffer[0..chunk_size]);
            remaining -= chunk_size;
        }
    }

    fn newline(writer: anytype) !void {
        try writer.writeByte('\n');
    }
};

const testing = std.testing;

test "format object with a trailing comment" {
    const a = testing.allocator;

    const input =
        \\{ "key" : "value"/*  Inline comment   */
        \\
        \\}
    ;
    const expected =
        \\{
        \\    "key": "value" /* Inline comment */
        \\}
    ;

    var parser = try JsonParser.init(a, input);
    defer parser.deinit(a);

    var parsed = try parser.parse(a);
    defer parsed.deinit(a);

    var formatted_string = try std.ArrayList(u8).initCapacity(a, input.len);
    defer formatted_string.deinit(a);

    const writer = formatted_string.writer(a);

    var formatter = Formatter.init(a, input, parser.positions, parser.comment_ranges);
    defer formatter.deinit();

    try formatter.format(a, parsed, writer);

    try testing.expectEqualStrings(expected, formatted_string.items);
}

test "format object with a leading comment" {
    const a = testing.allocator;

    const input =
        \\{
        \\      /* Leading comment*/
        \\   "key" : "value"
        \\
        \\}
    ;
    const expected =
        \\{
        \\    /* Leading comment */
        \\    "key": "value"
        \\}
    ;

    var parser = try JsonParser.init(a, input);
    defer parser.deinit(a);

    var parsed = try parser.parse(a);
    defer parsed.deinit(a);

    var formatted_string = try std.ArrayList(u8).initCapacity(a, input.len);
    defer formatted_string.deinit(a);

    const writer = formatted_string.writer(a);

    var formatter = Formatter.init(a, input, parser.positions, parser.comment_ranges);
    defer formatter.deinit();

    try formatter.format(a, parsed, writer);

    try testing.expectEqualStrings(expected, formatted_string.items);
}

test "format object has array value with a leading comment" {
    const a = testing.allocator;

    const input =
        \\{
        \\      /* Leading comment*/
        \\  "lang": "English",
        \\  "greeting": ["Good morning",   "Hello", "Good evening"]
        \\}
    ;
    const expected =
        \\{
        \\    /* Leading comment */
        \\    "lang": "English",
        \\    "greeting": ["Good morning", "Hello", "Good evening"]
        \\}
    ;

    var parser = try JsonParser.init(a, input);
    defer parser.deinit(a);

    var parsed = try parser.parse(a);
    defer parsed.deinit(a);

    var formatted_string = try std.ArrayList(u8).initCapacity(a, input.len);
    defer formatted_string.deinit(a);

    const writer = formatted_string.writer(a);

    var formatter = Formatter.init(a, input, parser.positions, parser.comment_ranges);
    defer formatter.deinit();

    try formatter.format(a, parsed, writer);

    try testing.expectEqualStrings(expected, formatted_string.items);
}

test "format" {
    const a = testing.allocator;

    const input =
        \\{
        \\    "game": "puzzle",
        \\  /* user configurable options
        \\  sound and difficulty */ 
        \\      "options": {"sound":   true,
        \\        "difficulty": 3     // max difficulty is 10
        \\  },
        \\
        \\    "powerups": ["speed" , "shield",   ]
        \\}
    ;

    const expected =
        \\{
        \\    "game": "puzzle",
        \\    /* user configurable options
        \\       sound and difficulty */
        \\    "options": {
        \\        "sound": true,
        \\        "difficulty": 3 // max difficulty is 10
        \\    },
        \\    "powerups": ["speed", "shield"]
        \\}
    ;

    var parser = try JsonParser.init(a, input);
    defer parser.deinit(a);

    var parsed = try parser.parse(a);
    defer parsed.deinit(a);

    var formatted_string = try std.ArrayList(u8).initCapacity(a, input.len);
    defer formatted_string.deinit(a);

    const writer = formatted_string.writer(a);

    var formatter = Formatter.init(a, input, parser.positions, parser.comment_ranges);
    defer formatter.deinit();

    try formatter.format(a, parsed, writer);

    try testing.expectEqualStrings(expected, formatted_string.items);
}
