# jsonc_fmt

A command-line formatter for JSON with Comments (JSONC) files.

## Overview

`jsonc_fmt` is a tool that formats JSONC text while preserving comments and improving readability. It works seamlessly with Unix pipes, making it easy to integrate into your workflow.

## Examples

### Simple formatting
```console
$ echo '{/*comment*/
∙ "key": 1}' | jsonc_fmt
{
    /* comment */
    "key": 1
}
```

### Complex formatting

Input file (`example.jsonc`):
```console
$ cat example.jsonc
{"game": "puzzle",
 /* user configurable options
 sound and difficulty */
"options": {"sound": true,
        "difficulty": 3         // max difficulty is 10
    },
"powerups": [   "speed", "shield"]
}
```

Format the file:
'''console
$ cat example.jsonc | jsonc_fmt
{
    "game": "puzzle",
    /* user configurable options
       sound and difficulty */
    "options": {
        "sound": true,
        "difficulty": 3 // max difficulty is 10
    },
    "powerups": ["speed", "shield"]
}
'''

## Installation

### For Nix users
You can try this tool without installing it permanently:

```console
// Run directly without installation
$ echo '{"key": "value"}' | nix run github:okonomipizza/jsonc_fmt

// or add to a temporary shell
$ nix shell github:okonomipizza/jsonc_fmt
$ echo '{"key": "value"}' | jsonc_fmt
```

### For Zig users
If you have the Zig compiler installed, you can build from source.
```console
$ mkdir jsonc_fmt_build
$ cd jsonc_fmt_build
$ git clone https://github.com/okonomipizza/jsonc_fmt.git
$ cd jsonc_fmt
$ zig build
$ echo '{"key": "value"}' | ./zig-out/bin/jsonc_fmt
```

## Usage
```console
// Format from stdin
$ echo '{"key": "value"}' | jsonc_fmt

// Format a file
$ cat input.jsonc | jsonc_fmt

// Save formatted output to a file
$ cat input.jsonc | jsonc_fmt > output.jsonc

// View help
$ jsonc_fmt -h
```

## Features
- Both `/* */` and `//` style comments are valid
- Works with Unix pipes for easy integration
