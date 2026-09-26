{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    rust-overlay,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
          inherit system;
          inherit overlays;
        };
        toolchain = pkgs.rust-bin.selectLatestNightlyWith (
          toolchain:
            toolchain.default.override {
              extensions = ["rust-src" "rust-analyzer" "llvm-tools"];
              targets = ["riscv32imc-unknown-none-elf"];
            }
        );
        esp-generate = pkgs.rustPlatform.buildRustPackage rec {
          pname = "esp-generate";
          version = "1.1.0";

          src = pkgs.fetchCrate {
            inherit pname version;

            sha256 = "sha256-debGfvVoxh9q1IabMHRAlJ0zeJdSWbo3lw/gp1JB6MQ=";
          };
          cargoBuildFlags = ["--locked"];
          cargoHash = "sha256-z9Tq6N1xPon+BPfdPnwg7XP7Pn3rPug9xxqS/MrtBMk=";
          doCheck = false;
        };
        espflash = pkgs.rustPlatform.buildRustPackage rec {
          pname = "espflash";
          version = "4.5.0";

          src = pkgs.fetchCrate {
            inherit pname version;

            sha256 = "sha256-Uz5zqbEyMeHuRSQZSC9xKK4yCvKnG5c14MHOgUfyrj4=";
          };
          cargoBuildFlags = ["--locked"];
          cargoHash = "sha256-QcvPdI0WeM/a6KZM4hRd2gFg8jmqSOzQtXFfyAMtxo8=";
          doCheck = false;
        };
        customEspRust = pkgs.stdenv.mkDerivation {
          name = "esp-rust";
          src =
            if system == "aarch64-linux"
            then
              pkgs.fetchurl {
                url = "https://github.com/esp-rs/rust-build/releases/download/v1.98.0.0/rust-1.98.0.0-aarch64-unknown-linux-gnu.tar.xz";
                hash = "sha256-WIGmnhH8rjJVZSE4sfDKhfBy4gb1hQ/s36eBcAh3L/8=";
              }
            else
              pkgs.fetchurl {
                url = "https://github.com/esp-rs/rust-build/releases/download/v1.98.0.0/rust-1.98.0.0-x86_64-unknown-linux-gnu.tar.xz";
                hash = "sha256-psPF7NUErUHdDw0vlcthl/lDucAsSO8IiM7cLy4RJ6Y=";
              };
          patchPhase = ''
            patchShebangs ./install.sh
          '';
          nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.zlib pkgs.stdenv.cc.cc.lib pkgs.gcc];
          installPhase = ''
            mkdir -p $out
            ./install.sh --destdir=$out --prefix="" --disable-ldconfig --without=rust-docs-json-preview,rust-docs
          '';
        };
        customEspSrc = pkgs.stdenv.mkDerivation {
          name = "esp-src";
          src = pkgs.fetchurl {
            url = "https://github.com/esp-rs/rust-build/releases/download/v1.98.0.0/rust-src-1.98.0.0.tar.xz";
            hash = "sha256-B/bE0QwjttirhjqeIX3uUYV0T0+i/j1iA7qHdNJ4Zh4=";
          };
          patchPhase = ''
            patchShebangs ./install.sh
          '';
          nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.zlib pkgs.stdenv.cc.cc.lib pkgs.gcc];
          buildInputs = [customEspRust];
          installPhase = ''
            mkdir -p $out
            cp -r ${customEspRust}/* $out
            chmod -R u+rw $out
            ./install.sh --destdir=$out --prefix="" --disable-ldconfig --without=rust-docs-json-preview,rust-docs
          '';
        };

        espGcc = pkgs.stdenv.mkDerivation {
          name = "esp-gcc";
          src =
            if system == "aarch64-linux"
            then
              pkgs.fetchurl {
                url = "https://github.com/espressif/crosstool-NG/releases/download/esp-16.1.0_20260609/xtensa-esp-elf-16.1.0_20260609-aarch64-linux-gnu.tar.xz";
                hash = "sha256-eF7iQr+9s6xOdk6F0vhxCcfF89pX10LamnxYwNCQYUk=";
              }
            else
              pkgs.fetchurl {
                url = "https://github.com/espressif/crosstool-NG/releases/download/esp-15.2.0_20250920/xtensa-esp-elf-15.2.0_20250920-x86_64-linux-gnu.tar.xz";
                hash = "sha256-49d60UVEgUUnu+ei0PeexFkqTiM5LFHHOIwOaGtqaXc=";
              };
          nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.zlib pkgs.stdenv.cc.cc];
          installPhase = ''
            mkdir -p $out
            cp -r * $out/
          '';
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # toolchain
            pkgs.minicom
            esp-generate
            espflash
            pkgs.qemu
            pkgs.probe-rs-tools
            espGcc
            customEspSrc
          ];
          ESP_RUST = "${customEspSrc}";
        };
      }
    );
}
