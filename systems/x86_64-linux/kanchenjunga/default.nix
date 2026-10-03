{
  inputs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  hostName = "kanchenjunga";
  backups = import ./backups.nix;
  vms = import ./vms.nix { inherit lib namespace; };
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  homelab = {
    profiles.server = enabled;
    metrics = enabled;
    inherit backups;
    inherit vms;

    hardware.vfio = enabled // {
      iommu = "amd";
      pciIds = [ ];
    };

    hardware.networking = enabled // {
      inherit hostName;
      domain = "direct.home.ishanjain.me";

      links =
        mkIfLink {
          name = "eth0";
          macAddress = "18:c0:4d:08:4d:54";
        }
        // mkIfLink {
          name = "eth1";
          macAddress = "18:c0:4d:08:4d:55";
        };

      netdevs = mkMerge [
        (mkBridgeIf "br0")
        (mkTaggedVlanIf 99)
      ];

      networks = mkMerge [
        {
          "30-uplinks" = {
            matchConfig.Name = [
              "en*"
              "eth*"
            ];
            networkConfig.Bridge = "br0";
            linkConfig.RequiredForOnline = "no";
            bridgeVLANs = [
              {
                VLAN = [
                  10
                  20
                  30
                  40
                  50
                  60
                  99
                  140
                  150
                  160
                ];
              }
            ];
          };

          "30-br0" = {
            matchConfig.Name = "br0";
            linkConfig.RequiredForOnline = "no";
            vlan = [ "vlan99" ];
            bridgeVLANs = [ { VLAN = [ 99 ]; } ];
          };
        }
        (mkNetworkIf {
          name = "vlan99";
          config = {
            networkConfig = {
              Description = "Tagged VLAN99 interface for accessing the host";
              DHCP = "ipv4";
              LinkLocalAddressing = "ipv6";
              IPv6LinkLocalAddressGenerationMode = "eui64";
              IPv6PrivacyExtensions = "no";
              IPv6AcceptRA = "yes";
              LLDP = "yes";
              EmitLLDP = "yes";
              LLMNR = "no";
            };
            ipv6AcceptRAConfig = {
              DHCPv6Client = false;
              Token = "eui64";
            };
          };
        })
      ];

      tcpPorts = [ 22 ];
    };

    system.boot = enabled // {
      secure = disabled;
      timeout = 5;
    };
  };

  sops.secrets.tailscale-auth-key = {
    sopsFile = "${inputs.self}/secrets/tailscale/auth-key";
    format = "binary";
  };

  system.stateVersion = "26.05";
}
