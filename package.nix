{
  lib,
  stdenv,
  zig,
  fetchFromGitHub,
  revision ? "dirty",
  optimize ? "Debug",
}: let
  zig-clap = fetchFromGitHub {
    owner = "Hejsil";
    repo = "zig-clap";
    rev = "5289e0753cd274d65344bef1c114284c633536ea";
    sha256 = "sha256-XytqwtoE0xaR43YustgK68sAQPVfC0Dt+uCs8UTfkbU=";
  };
  jsonpico = fetchFromGitHub {
    owner = "okonomipizza";
    repo = "jsonpico";
    rev = "8798d0f20b6baf4f7d16f9eea471828c6af4d2c6";
    sha256 = "sha256-yR4No27Oph9IhzJ4EwzgQsHIwKstI9YcbWx70K3M0F4=";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "jsonc_fmt";
    version = "0.1.0";

    src = ./.;

    nativeBuildInputs = [
      zig
    ];

      configurePhase = ''
        runHook preConfigure
        
        export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
        mkdir -p $ZIG_GLOBAL_CACHE_DIR
        
        cp build.zig.zon build.zig.zon.backup
        
        # Copy dependencies to local directory
        mkdir -p ./deps/clap
        cp -r ${zig-clap}/* ./deps/clap/
        chmod -R +w ./deps/clap

        mkdir -p ./deps/jsonpico
        cp -r ${jsonpico}/* ./deps/jsonpico/
        chmod -R +w ./deps/jsonpico
        
        # Revise build.zig.zon to build
        cat > build.zig.zon << 'EOF'
    .{
        .name = .jsonc_fmt,
        .version = "0.1.0",
        .fingerprint =  0xc406def53260aa41,
        .minimum_zig_version = "0.15.1",
        .dependencies = .{
            .clap = .{
                .path = "./deps/clap",
            },
            .jsonpico = .{
                .path = "./deps/jsonpico",
            },
        },
        .paths = .{
            "build.zig",
            "build.zig.zon", 
            "src",
        },
    }
    EOF
        
        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild
        zig build --prefix $out -Doptimize=${optimize} --verbose
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        # zig build with --prefix should handle installation
        runHook postInstall
      '';


    meta = {
      description = "A JSON with Comments formatter written in Zig";
      homepage = "https://github.com/your-username/jsonc-fmt";
      license = lib.licenses.mit;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mainProgram = "jsonc_fmt";
    };
  })
