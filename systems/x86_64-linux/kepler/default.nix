{ lib, pkgs, namespace, ... }:
with lib;
with lib.${namespace};
let hostName = "kepler";
in {
  imports = [ ./disk-config.nix ./hardware-configuration.nix ];

  homelab = {
    server = enabled;

    hardware.networking = {
      inherit hostName;
      tcpPorts = [ 22 ];
    };

    system.boot = enabled // {
      secure = disabled;
      timeout = 10;
    };
  };

  # Enable passwordless sudo.
  security.sudo.extraRules = [{
    users = [ "ishan" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];

  services.openssh = enabled // {
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  systemd.targets.multi-user.enable = true;

  nix = mkNixConfig { inherit lib pkgs; } // { optimise.automatic = true; };

  users = {
    mutableUsers = false;
    users.ishan = {
      uid = 1000;
      extraGroups = [ "wheel" "networkmanager" ];
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

