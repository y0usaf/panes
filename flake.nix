{
  description = "Panes - Agent Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;

        pname = "panes";
        version = "0.38.0";
        src = ./.;

        # Fetch npm deps using package-lock.json (reproducible fixed-output derivation)
        npmDeps = pkgs.fetchNpmDeps {
          inherit src;
          npmDepsFetcherVersion = 2;
          hash = "sha256-r1s1JkzHgO30BLiSS2wWfIQjGwRWaaJW28hETTxigR8=";
        };

        # Build Vite frontend + esbuild sidecar using bun to run scripts
        frontend = pkgs.stdenv.mkDerivation {
          name = "${pname}-frontend";
          inherit src;
          nativeBuildInputs = with pkgs; [
            nodejs
            bun
            npmHooks.npmConfigHook
          ];
          inherit npmDeps;
          buildPhase = ''
            export HOME=$TMPDIR
            npm ci --legacy-peer-deps
            patchShebangs --build node_modules
            bun run build
            bun run build:claude-sidecar
          '';
          installPhase = ''
            mkdir -p $out
            cp -r dist $out/dist
            cp -r src-tauri/sidecar-dist $out/sidecar-dist
          '';
        };
      in {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          inherit pname version;
          src = ./.;

          postUnpack = ''
            sourceRoot=$(echo */src-tauri)
          '';

          cargoLock.lockFile = ./src-tauri/Cargo.lock;

          doCheck = false;

          nativeBuildInputs = with pkgs; [
            pkg-config
            wrapGAppsHook3
            gobject-introspection
            nodejs
            perl
          ];

          buildInputs = with pkgs; [
            at-spi2-atk
            cairo
            gdk-pixbuf
            glib
            gtk3
            librsvg
            libsoup_3
            openssl
            pango
            webkitgtk_4_1
            libayatana-appindicator
          ];

          preBuild = ''
            cp -r ${frontend}/dist ../dist
            cp -r ${frontend}/sidecar-dist sidecar-dist
            export PANES_SKIP_DESKTOP_PREBUILD=1
          '';

          postInstall = ''
            # Install sidecar next to binary so PANES_SIDECAR_PATH can find it
            mkdir -p $out/share/panes
            cp ${frontend}/sidecar-dist/claude-agent-sdk-server.mjs $out/share/panes/
          '';

          # Add claude + node + bun to PATH, and point to sidecar via wrapGAppsHook
          preFixup = ''
            gappsWrapperArgs+=(
              --prefix PATH : /run/current-system/sw/bin
              --prefix PATH : ${lib.makeBinPath [pkgs.nodejs pkgs.bun]}
              --set PANES_SIDECAR_PATH "$out/share/panes/claude-agent-sdk-server.mjs"
              --set CLAUDE_BINARY_PATH /run/current-system/sw/bin/claude
              --unset CLAUDECODE
            )
          '';

          meta = with lib; {
            description = "Agent Development Environment for orchestrating AI agents";
            homepage = "https://panesade.com";
            license = licenses.mit;
            platforms = ["x86_64-linux" "aarch64-linux"];
            mainProgram = "Panes";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bun
            nodejs
            cargo
            rustc
            pkg-config
            webkitgtk_4_1
            libsoup_3
            gtk3
            openssl
            libayatana-appindicator
            gobject-introspection
          ];
        };
      }
    );
}
