{
  description = "devshell for a Rust project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  inputs.devshell.url = "github:numtide/devshell";
  inputs.devshell.inputs.nixpkgs.follows = "nixpkgs";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.flake-compat.url = "github:nix-community/flake-compat";
  inputs.flake-compat.flake = false;

  inputs.fenix.url = "github:nix-community/fenix";
  inputs.fenix.inputs.nixpkgs.follows = "nixpkgs";

  inputs.crane.url = "github:ipetkov/crane";
  inputs.crane.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      nixpkgs,
      crane,
      devshell,
      fenix,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ devshell.overlays.default ];
        };

        rustStable = (import fenix { inherit pkgs; }).fromToolchainFile {
          file = ./toolchain.toml;
          sha256 = "sha256-6eN/GKzjVSjEhGO9FhWObkRFaE1Jf+uqMSdQnb8lcB4=";
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain rustStable;

        custom-package = craneLib.buildPackage {
          src = craneLib.cleanCargoSource (craneLib.path ./.);
          buildInputs = [ ];
          nativeBuildInputs = [ ];
          cargoClippyExtraArgs = "--all-targets -- --deny warnings";
        };
      in
      {
        checks = {
          inherit custom-package;
        };

        packages.default = custom-package;

        apps.default = flake-utils.lib.mkApp { drv = custom-package; };

        devShells.default = pkgs.devshell.mkShell {
          env = [
            {
              name = "DEVSHELL_NO_MOTD";
              value = 1;
            }
          ];

          packages = with pkgs; [
            gcc
            just
            libressl
            rustStable
          ];
        };
      }
    );
}
