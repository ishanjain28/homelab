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
      # url = "github:szlend/deploy-rs/fix-show-derivation-parsing";
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
  };

  outputs = inputs@{ deploy-rs, self, ... }:
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
    in lib.mkFlake {
      inherit inputs;
      src = ./.;

      deploy = lib.mkDeploy { inherit (inputs) self; };

      devShells.x86_64-linux.default =
        let pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
        in pkgs.mkShell {
          packages = [ inputs.deploy-rs.packages.${pkgs.system}.deploy-rs ];
        };

      systems = with inputs; {
        modules = {
          nixos = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            nixos-generators.nixosModules.all-formats
          ];
        };
        hosts = { kepler.modules = [ ]; };
      };

      outputs-builder = channels: {
        formatter =
          (treefmtModule channels.nixpkgs ./treefmt.nix).config.build.wrapper;
      };
    } // {
      inherit (inputs) self;
    };
}

