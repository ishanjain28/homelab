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

    services = {
      pvr-movies-monitor = enabled // {
        host = "0.0.0.0";
        port = "3000";
        apiKey = "test-key";
      };
    };

    hardware.networking = {
      inherit hostName;

      enable = true;
      domain = "direct.home.ishanjain.me";
      tcpPorts = [ 22 ];
      vlans = {
        vlan50 = {
          id = 50;
          interface = "ens19";
        };
      };
      interfaces = {
        vlan50 = {
          name = "vlan50";
          macAddress = "00:11:22:33:44:01";
          mtu = 1500;
          useDHCP = true;
        };
      };
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

  services = {
    openssh = enabled // {
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };
  };

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
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAX88KLYCUWS1IKTGsgIRIHwGxTyfhsiRyAgtv65GEEm ishan@turquoise"
      ];
      isNormalUser = false;
      ignoreShellProgramCheck = true;
      shell = pkgs.fish;
    };
  };

  environment.shells = with pkgs; [ fish ];

  system.stateVersion = "25.11";
}
