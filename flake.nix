{
  description = "Ishan's homelab configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-compat = {
      url = "github:nix-community/flake-compat";
      flake = false;
    };

    flake-utils.url = "github:numtide/flake-utils";

    flake-utils-plus = {
      url = "github:gytis-ivaskevicius/flake-utils-plus";
      inputs.flake-utils.follows = "flake-utils";
    };

    snowfall-lib = {
      url = "github:snowfallorg/lib/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils-plus.follows = "flake-utils-plus";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.flake-compat.follows = "flake-compat";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, ... }:
    let
      lib = inputs.snowfall-lib.mkLib {
        inherit inputs;
        src = ./.;
        snowfall = {
          namespace = "homelab";
          meta = {
            name = "ishan-nix-configs";
            title = "Ishan's Nix configuration";
          };
        };
      };
      treefmtModule = inputs.treefmt-nix.lib.evalModule;
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      hostRegistries = builtins.mapAttrs (
        _hostName: machine: machine.config.system.homelab.registry
      ) self.nixosConfigurations;
      fleetRegistry = lib.mkFleetRegistry hostRegistries;
      configCommand =
        pkgs:
        pkgs.writeShellApplication {
          name = "config";
          runtimeInputs = with pkgs; [
            coreutils
            nix
          ];
          text = ''
            set -euo pipefail

            flake="''${HOMELAB_FLAKE:-.}"

            usage() {
              echo "usage: config gatus" >&2
              exit 2
            }

            target="''${1:-}"
            shift || true

            case "$target" in
              gatus)
                [[ $# -eq 0 ]] || usage
                config_attr="configs.gatus"
                ;;
              *)
                usage
                ;;
            esac

            path="$(
              nix --option eval-cache false build --no-link --print-out-paths \
                "$flake#$config_attr"
            )"
            printf '##########\n## Config: %s\n##########\n\n' "$target"
            cat "$path"
          '';
        };
      inherit ((import ./lib/module/default.nix { lib = inputs.nixpkgs.lib; })) shellAliases;
      shellAliasHook = inputs.nixpkgs.lib.concatStringsSep "\n" (
        inputs.nixpkgs.lib.mapAttrsToList (
          name: command: "alias ${name}=${inputs.nixpkgs.lib.escapeShellArg command}"
        ) shellAliases
      );
      mkDevShell =
        system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
        in
        pkgs.mkShell {
          packages = [
            (configCommand pkgs)
            pkgs.age
            inputs.deploy-rs.packages.${system}.deploy-rs
            pkgs.git
            pkgs.sops
          ];
          shellHook = shellAliasHook;
        };
    in
    lib.mkFlake {
      inherit inputs;
      src = ./.;
      inherit supportedSystems;

      channels-config.allowUnfreePredicate =
        package:
        builtins.elem (inputs.nixpkgs.lib.getName package) [
          "mongodb-ce"
          "omada-controller"
          "timescaledb"
          "windmill"
        ];

      deploy = lib.mkDeploy {
        inherit (inputs) self;
        inherit fleetRegistry;
      };

      devShells = inputs.nixpkgs.lib.genAttrs supportedSystems (system: {
        default = mkDevShell system;
      });

      systems = with inputs; {
        modules = {
          nixos = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            nixos-generators.nixosModules.all-formats
            sops-nix.nixosModules.sops
          ];
        };
        hosts = {
          annapurna.modules = [ ];
          kanchenjunga.modules = [ ];
          kepler.modules = [ ];
        };
      };

      outputs-builder = channels: {
        formatter = (treefmtModule channels.nixpkgs ./treefmt.nix).config.build.wrapper;
        packages.volume = channels.nixpkgs.callPackage ./packages/volume { };
      };

      templates = {
        rust.description = "devshell for Rust projects";
      };
    }
    // {
      inherit (inputs) self;
      configs = {
        gatus = self.nixosConfigurations.kepler.config.services.gatus.configFile;
      };
      lib = lib // {
        homelabRegistry = fleetRegistry;
      };
    };
}
