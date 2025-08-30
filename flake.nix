{
  inputs = rec {
    nixpkgs.url = github:NixOS/nixpkgs/release-25.05;
    flake-utils.url = github:numtide/flake-utils;
    zig-overlay.url = github:mitchellh/zig-overlay;
    zls-overlay.url = github:zigtools/zls;
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    zig = inputs.zig-overlay.packages.x86_64-linux.default;
    zls = inputs.zls-overlay.packages.x86_64-linux.zls.overrideAttrs (old: {
            nativeBuildInputs = [ zig ];
    });
  in
    {
        devShells.x86_64-linux.default = pkgs.mkShell {
            packages = with pkgs; [
                zls
                zig
            ];
        };
    };
}

