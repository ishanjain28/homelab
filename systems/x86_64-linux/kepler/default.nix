{
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  hostName = "kepler";
  inherit mkMigratableContainerVolume mkBridgeIf mkTaggedVlanIf;
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  homelab = {
    server = enabled;

    services = {
      ssh = enabled // {
        addRootKeys = true;
        passwordAuth = false;
        permitRootLogin = true;
      };

      pvr-movies-monitor = enabled // {
        host = "0.0.0.0";
        port = 3000;
        apiKey = "test-key";
        volumeConfig = {
          root = mkMigratableContainerVolume {
            name = "pvr-movies-monitor";
            size = "1G";
            containerPath = "/var/lib/pvr-monitor";
            uuid = "63d76b1a-8531-4836-8961-7360f068697b";
          };
        };
      };
    };

    hardware.networking = enabled // {
      inherit hostName;

      domain = "direct.home.ishanjain.me";
      # Rename PHYs to values I like using the permanent
      # MAC address as reference.
      links = mkIfLinks [
        {
          name = "eth0";
          macAddress = "DC:24:11:DE:01:EF";
        }
      ];

      netdevs = lib.mkMerge [
        # Creates a VLAN aware bridge on the host
        (mkBridgeIf "br0")
        # A interface on VLAN99 on the host for accessing it.
        (mkTaggedVlanIf 99)
      ];

      networks = lib.mkMerge [
        {
          # Add PHYs to the Bridge
          "30-uplinks" = {
            matchConfig.Name = "eth*";
            networkConfig.Bridge = "br0";
            # Add VLANs to the Trunk Port
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
            # Add VLAN99 interface to the bridge to access the host.
            vlan = [ "vlan99" ];
            # Add VLANs to the Bridge (CPU)
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
          # Container Trunk Ports (Host-side of the veth)
          "30-ve-containers" = {
            matchConfig.Name = "ve-*"; # Matches nspawn default veth prefix
            networkConfig.Bridge = "br0";
          };
        }
        (mkNetworkIf {
          name = "vlan99";
          config = {
            Description = "Tagged VLAN99 interface for accessing the host";
            DHCP = "yes";
            IPv6AcceptRA = "yes";
            LLDP = "no";
            EmitLLDP = "no";
            LLMNR = "no";
          };
        })
      ];

      # networks = mkNetworkIfList [{
      #   name = "hvlan99";
      #   config = {
      #     Description = "Tagged VLAN99 interface for accessing the host";
      #     DHCP = "yes";
      #     IPv6AcceptRA = "yes";
      #     LLDP = "no";
      #     EmitLLDP = "no";
      #     LLMNR = "no";
      #   };
      # }
      # {
      #   name = "hvlan10";
      #   config = {
      #     Description = "Passthrough VLAN10 interface for applications";
      #     KeepConfiguration = "yes";
      #     LinkLocalAddressing = "no";
      #     IPv6AcceptRA = "no";
      #     LLMNR = "no";
      #     EmitLLDP = "no";
      #     LLDP = "no";
      #   };
      # }
      # {
      #   name = "hvlan50";
      #   config = {
      #     Description = "Passthrough VLAN50 interface for applications";
      #     KeepConfiguration = "yes";
      #     LinkLocalAddressing = "no";
      #     IPv6AcceptRA = "no";
      #     LLDP = "no";
      #     EmitLLDP = "no";
      #     LLMNR = "no";
      #   };
      # }
      #  ];

      tcpPorts = [ 22 ];
    };

    system.boot = enabled // {
      secure = disabled;
      timeout = 5;
    };
  };

  # Enable passwordless sudo.
  security.sudo.extraRules = [
    {
      users = [ "ishan" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  systemd.targets.multi-user.enable = true;

  nix = mkNixConfig { inherit lib pkgs; } // {
    optimise.automatic = true;
  };

  users = {
    mutableUsers = false;
    users.ishan = {
      uid = 1000;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      isSystemUser = true;
      group = "users";
      createHome = true;
      home = "/home/ishan";
      homeMode = "700";
      useDefaultShell = true;
      isNormalUser = false;
      ignoreShellProgramCheck = true;
      shell = pkgs.fish;
      hashedPassword = "$6$/4l0PEwOs7lcQlOU$rn9VlGaNJQcd.ndc.vmkIo4ZbL6uG9G3sd/mP7/AFf9ucakIfnGT4NtWllnEPnoLg5FsoHzJgpfHuDoAzNLXC/";
    };
  };

  environment.shells = with pkgs; [ fish ];

  system.stateVersion = "26.05";
}
