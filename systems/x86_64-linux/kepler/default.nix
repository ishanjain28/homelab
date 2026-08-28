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
    logging = enabled // {
      lokiPushUrl = "http://10.0.50.23:3100/loki/api/v1/push";
    };

    volumes = {
      actual-server = {
        uuid = "7adaa473-69d9-46cd-9328-0ad971095e62";
        host = hostName;
        ownerService = "actual-server";
        mountPath = "/var/lib/actual-server";
        size = "512M";
        migratable = true;
        mode = "0700";
      };

      grafana = {
        uuid = "ad555d93-40a2-40ae-90eb-e3c6c591ef65";
        host = hostName;
        ownerService = "grafana";
        mountPath = "/var/lib/grafana";
        size = "256M";
        migratable = true;
        mode = "0700";
      };

      seerr = {
        uuid = "51b42873-9fd6-47d2-aa7c-71af578c4f05";
        host = hostName;
        ownerService = "seerr";
        mountPath = "/var/lib/seerr";
        size = "5G";
        migratable = true;
        mode = "0700";
      };

      loki = {
        uuid = "9f67c61c-3d4c-45d2-b4df-6f1775331d9b";
        host = hostName;
        ownerService = "loki";
        mountPath = "/var/lib/loki";
        size = "20G";
        migratable = true;
        mode = "0700";
      };
    };

    services = {
      ssh = enabled // {
        addRootKeys = true;
        passwordAuth = false;
        permitRootLogin = false;
      };

      pvr-movies-monitor = enabled // {
        vlan = 50;
        runtimeId = 20691;
        monitor = enabled // {
          protocol = "tcp";
        };
        # volumes = [ "pvr-movies-monitor" ];
      };

      huawei-sms-telegram = enabled // {
        vlan = 50;
        runtimeId = 27777;
        monitor = disabled;
      };

      bentopdf = enabled // {
        vlan = 50;
        runtimeId = 50715;
      };

      lldap = enabled // {
        vlan = 50;
        runtimeId = 25457;
      };

      authelia = enabled // {
        vlan = 50;
        runtimeId = 20001;
      };

      grafana = enabled // {
        vlan = 50;
        runtimeId = 31918;
        volumes = [ "grafana" ];
      };

      mathesar = enabled // {
        vlan = 50;
        runtimeId = 30339;
      };

      seerr = enabled // {
        vlan = 50;
        runtimeId = 30340;
        volumes = [ "seerr" ];
      };

      actual-server = enabled // {
        vlan = 50;
        runtimeId = 30341;
        volumes = [ "actual-server" ];
      };

      tracearr = enabled // {
        vlan = 50;
        runtimeId = 30342;
      };

      loki = enabled // {
        vlan = 50;
        runtimeId = 30343;
        volumes = [ "loki" ];
      };

      gatus = disabled // {
        vlan = 50;
        runtimeId = 36924;
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
