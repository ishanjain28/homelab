{
  inputs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  hostName = "kepler";
  backups = import ./backups.nix;
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
    metrics = enabled;

    inherit backups;
    inherit volumes;
    services = workloads;

    hardware.networking = enabled // {
      inherit hostName;

      domain = "home.direct.ishanjain.me";
      # Rename PHYs to values I like using the permanent
      # MAC address as reference.
      links = mkIfLink {
        name = "eth0";
        macAddress = "DC:24:11:DE:01:EF";
      };

      netdevs = mkMerge [
        # Creates a VLAN aware bridge on the host
        (mkBridgeIf "br0")
        # A interface on VLAN99 on the host bridge for accessing the host.
        (mkTaggedVlanIf 99)
      ];

      networks = mkMerge [
        {
          # Add PHYs to the Bridge
          "30-uplinks" = {
            matchConfig.Name = "eth*";
            networkConfig = {
              Bridge = "br0";
            };
            # Kepler is temporarily nested inside Proxmox. Mark the VM uplink
            # as the multicast-router port so IGMP reports cross both bridges.
            # Remove this when Kepler moves to bare metal.
            bridgeConfig.MulticastRouter = "permanent";
            linkConfig.RequiredForOnline = "no";
            # Add allowed VLANs to the Trunk Port
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
          # Attach the Host Management VLAN to the Bridge.
          "30-br0" = {
            matchConfig.Name = "br0";
            linkConfig.RequiredForOnline = "no";
            # Add VLAN99 interface to the bridge to access the host.
            vlan = [ "vlan99" ];
            # Add VLAN to the Bridge (CPU)
            bridgeVLANs = [ { VLAN = [ 99 ]; } ];
          };
          # "30-vb-vlan99-containers" = {
          #   matchConfig.Name = "vb-a*"; # Matches nspawn default vbridge prefix
          #   networkConfig.Bridge = "br0";
          #   bridgeVLANs = [{ VLAN = [ 99 ]; }];
          # };
        }
        (mkNetworkIf {
          name = "vlan99";
          config = {
            linkConfig.MACAddress = mkMacAddress "${hostName}:99";
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
    sopsFile = "${inputs.self}/secrets/tailscale/auth-key";
    format = "binary";
  };

  system.stateVersion = "26.05";
}
