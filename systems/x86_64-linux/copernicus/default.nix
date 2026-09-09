{ lib, namespace, ... }:
with lib;
with lib.${namespace};
let
  hostName = "copernicus";
  volumes = import ./volumes.nix;
  workloads = import ./workloads.nix { inherit lib namespace; };
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  homelab = {
    profiles.server = enabled;
    inherit volumes;
    services = workloads;

    hardware.networking = enabled // {
      inherit hostName;
      domain = "direct.home.ishanjain.me";

      # Rename PHYs to values I like using the permanent
      # MAC address as reference.
      links = mkIfLink {
        name = "eth0";
        macAddress = "BC:24:11:94:DD:90";
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
                  70
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
              LLDP = "no";
              EmitLLDP = "no";
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
    sopsFile = ../../../secrets/tailscale/auth-key;
    format = "binary";
  };

  system.stateVersion = "26.05";
}
