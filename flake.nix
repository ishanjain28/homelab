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

    devshell = {
      url = "github:numtide/devshell";
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
      mkGeneratedConfigCommand =
        pkgs:
        { name, fileAttr }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            nix
          ];
          text = ''
            set -euo pipefail

            host="''${1:-kepler}"
            flake="''${HOMELAB_FLAKE:-.}"
            base="$flake#nixosConfigurations.$host.config"

            build_path() {
              nix --option eval-cache false build --no-link --print-out-paths "$base.$1"
            }

            path="$(build_path '${fileAttr}')"
            printf '##########\n## Host: %s\n##########\n\n' "$host"
            cat "$path"
          '';
        };
      generatedConfigCommands = pkgs: [
        (mkGeneratedConfigCommand pkgs {
          name = "gatus";
          fileAttr = "services.gatus.configFile";
        })
      ];
      volumeCommand = pkgs: import ./lib/dev-shell/volume.nix { inherit pkgs; };
      shellAliasCommands =
        pkgs:
        let
          mkGitAlias =
            name: args:
            pkgs.writeShellApplication {
              inherit name;
              runtimeInputs = [ pkgs.git ];
              text = ''
                exec git ${args} "$@"
              '';
            };
        in
        [
          (mkGitAlias "g" "")
          (mkGitAlias "gst" "status")
          (mkGitAlias "gds" "diff --staged")
          (mkGitAlias "gp" "pull")
          (mkGitAlias "gd" "diff")
          (mkGitAlias "gcp" "cherry-pick")
        ];
    in
    lib.mkFlake {
      inherit inputs;
      src = ./.;
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      deploy = lib.mkDeploy { inherit (inputs) self; };

      devShells.aarch64-linux.default =
        let
          pkgs = import inputs.nixpkgs { system = "aarch64-linux"; };
        in
        pkgs.mkShell {
          packages =
            (generatedConfigCommands pkgs)
            ++ (shellAliasCommands pkgs)
            ++ [
              (volumeCommand pkgs)
              pkgs.age
              inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
              pkgs.sops
            ];
        };

      devShells.x86_64-linux.default =
        let
          pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
        in
        pkgs.mkShell {
          packages =
            (generatedConfigCommands pkgs)
            ++ (shellAliasCommands pkgs)
            ++ [
              (volumeCommand pkgs)
              pkgs.age
              inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.deploy-rs
              pkgs.sops
            ];
        };

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
    };
}
