{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/25.11";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    rust-overlay,
    nixpkgs,
  }: let
    overlays = [(import rust-overlay)];
    pkgs = import nixpkgs {
      system = "x86_64-linux";
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
      version = "4.3.0";

      src = pkgs.fetchCrate {
        inherit pname version;

        sha256 = "sha256-V6SfKKHf+Wx/BvxIJetEjQzZzjVMpjbiQ/coA+lYBQY=";
      };
      cargoBuildFlags = ["--locked"];
      cargoHash = "sha256-VRXx9b/Pr6Kcmty/HrKZdtOO/gBqidJvDU8osdaEYvY=";
      doCheck = false;
    };
    customEspRust = pkgs.stdenv.mkDerivation {
      name = "esp-rust";
      src = pkgs.fetchurl {
        url = "https://github.com/esp-rs/rust-build/releases/download/v1.90.0.0/rust-1.90.0.0-x86_64-unknown-linux-gnu.tar.xz";
        hash = "sha256-GmHoiEIVdOQbg72rNtSpg1GqYvV1tVXBtJczZprFacc=";
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
        url = "https://github.com/esp-rs/rust-build/releases/download/v1.90.0.0/rust-src-1.90.0.0.tar.xz";
        hash = "sha256-BqSkAyX0ftKGBXIzYV3WtT5zjF59QE2T1DZO2fZNpZk=";
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
      src = pkgs.fetchurl {
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
    devShell.x86_64-linux = pkgs.mkShell {
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
  };
}
