{
    mkShell,
    zig,
    system,
    pkgs,
}: let

  in
    mkShell {
      name = "jsonc-fmt";
      packages =
        [
          zig
        ];
    }
