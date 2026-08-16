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
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  homelab = {
    server = enabled;
    secrets = enabled;

    services = {
      ssh = enabled // {
        addRootKeys = true;
        passwordAuth = false;
        permitRootLogin = true;
      };

      pvr-movies-monitor = enabled // {
        vlan = 50;
        monitor = enabled // {
          protocol = "tcp";
        };
        volumeConfig = {
          root = mkMigratableContainerVolume {
            name = "pvr-movies-monitor";
            size = "1G";
            containerPath = "/var/lib/pvr-monitor";
            uuid = "63d76b1a-8531-4836-8961-7360f068697b";
          };
        };
      };

      huawei-sms-telegram = enabled // {
        vlan = 50;
        monitor = disabled;
      };

      bentopdf = enabled // {
        vlan = 50;
      };

      lldap = enabled // {
        vlan = 50;
        httpUrl = "https://ldap.ishanjain.me";
        ldapBaseDn = "dc=ishanjain,dc=me";
        ldapUserEmail = "admin@direct.home.ishanjain.me";
      };

      redis = enabled // {
        vlan = 50;
        port = 6379;
        bind = "0.0.0.0";
        maxmemory = "256mb";
      };

      grafana = enabled // {
        vlan = 50;
        port = 3000;
      };

      mathesar = enabled // {
        vlan = 50;
        port = 5001;
      };

      gatus = disabled // {
        vlan = 50;
        port = 8080;
        externalEndpoints = [ ];
      };
    };

    hardware.networking = enabled // {
      inherit hostName;

      domain = "direct.home.ishanjain.me";
      # Rename PHYs to values I like using the permanent
      # MAC address as reference.
      links = mkIfLink {
        name = "eth0";
        macAddress = "DC:24:11:DE:01:EF";
      };

      netdevs = lib.mkMerge [
        # Creates a VLAN aware bridge on the host
        (mkBridgeIf "br0")
        # A interface on VLAN99 on the host bridge for accessing the host.
        (mkTaggedVlanIf 99)
      ];

      networks = lib.mkMerge [
        {
          # Add PHYs to the Bridge
          "30-uplinks" = {
            matchConfig.Name = "eth*";
            networkConfig = {
              Bridge = "br0";
            };
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
            Description = "Tagged VLAN99 interface for accessing the host";
            DHCP = "yes";
            IPv6AcceptRA = "yes";
            LLDP = "no";
            EmitLLDP = "no";
            LLMNR = "no";
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

  systemd.targets.multi-user = enabled;

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
