{
  nixpkgs,
  system ? builtins.currentSystem,
}:
let
  baseLib = import (nixpkgs + "/lib");
  lib = baseLib.extend (
    self: _: {
      homelab =
        (import ../../lib/networking/default.nix { lib = self; })
        // {
          mkContainerVethName =
            name: vlan: "v${builtins.substring 0 9 (builtins.hashString "sha256" "${name}:${toString vlan}")}-${toString vlan}";
        }
        // (import ../../lib/firewall/default.nix {
          lib = self;
          namespace = "homelab";
        });
    }
  );
  fixture = import ./fixture.nix { inherit lib; };
  result = import (nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit lib;
    inherit system;
    specialArgs = {
      namespace = "homelab";
      inputs = { };
    };
    modules = [
      ../../modules/nixos/platform/firewall
      ({ lib, ... }: {
        options.system.homelab.registry = lib.mkOption {
          type = lib.types.attrs;
          default.services = { };
        };
        config = {
          system.stateVersion = "26.05";
          networking.hostName = "test";
          boot.isContainer = true;
          homelab.firewall = {
            enable = true;
            peerServices = { };
            inventory = fixture.args.inventory;
            ipv4File = ./ipv4.json;
            extraServices = lib.mapAttrs' (
              _: s:
              lib.nameValuePair s.name {
                inherit (s) endpoints networkPolicy;
                attachments."50" = s.attachments."50" // {
                  interface = "ve-${s.name}";
                };
              }
            ) (lib.filterAttrs (_: s: s.name != "u") fixture.args.services);
          };
          containers = lib.genAttrs [ "a" "b" ] (name: {
            privateNetwork = true;
            hostBridge = "br0";
            localMacAddress = fixture.args.services."test/${name}".attachments."50".mac;
            config.system.stateVersion = "26.05";
          });
        };
      })
    ];
  };
in
{
  inherit (result) config;
  checks = {
    assertions = map (a: a.message) (builtins.filter (a: !a.assertion) result.config.assertions);
    retainOnStop = result.config.systemd.services.nftables.serviceConfig.ExecStop == [ ];
    bound = builtins.elem "nftables.service" result.config.systemd.services."container@a".bindsTo;
    ordered = builtins.elem "nftables.service" result.config.systemd.services."container@a".after;
    rules = result.config.networking.nftables.tables.homelab_services.content;
  };
}
