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
  inherit mkMigratableContainerVolume;
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
        port = "3000";
        apiKey = "test-key";
        volumeConfig = {
          root = mkMigratableContainerVolume {
            name = "pvr-movies-monitor";
            size = "5G";
            containerPath = "/var/lib/pvr-monitor";
            uuid = "63d76b1a-8531-4836-8961-7360f068697b";
          };
        };
      };
    };

    # systemd.network.links."10-wan" = {
    #   matchConfig.MACAddress = "bc:24:11:de:01:ed";
    #   linkConfig.Name = "eth0";
    # };

    hardware.networking = {
      inherit hostName;

      enable = true;
      domain = "direct.home.ishanjain.me";
      tcpPorts = [ 22 ];
    };

    system.boot = enabled // {
      secure = disabled;
      timeout = 10;
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
    };
  };

  environment.shells = with pkgs; [ fish ];

  system.stateVersion = "26.05";
}
