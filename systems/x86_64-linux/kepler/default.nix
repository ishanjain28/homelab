{ lib, pkgs, namespace, ... }:
with lib;
with lib.${namespace};
let hostName = "kepler";
in {
  imports = [ ./hardware-configuration.nix ];

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = hostName;

  # Enable networking
  networking.networkmanager.enable = true;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_IN";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_IN";
    LC_IDENTIFICATION = "en_IN";
    LC_MEASUREMENT = "en_IN";
    LC_MONETARY = "en_IN";
    LC_NAME = "en_IN";
    LC_NUMERIC = "en_IN";
    LC_PAPER = "en_IN";
    LC_TELEPHONE = "en_IN";
    LC_TIME = "en_IN";
  };

  time.timeZone = "Asia/Kolkata";

  # Enable passwordless sudo.
  security.sudo.extraRules = [{
    users = [ "kepler" ];
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

  users.users.kepler.packages = with pkgs; [ nix-output-monitor ];

  users = {
    mutableUsers = false;
    users.kepler = {
      uid = 1000;
      extraGroups = [ "wheel" "networkmanager" ];
      isSystemUser = true;
      group = "users";
      createHome = true;
      home = "/home/kepler";
      homeMode = "700";
      useDefaultShell = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAX88KLYCUWS1IKTGsgIRIHwGxTyfhsiRyAgtv65GEEm ishan@turquoise"
      ];
      isNormalUser = false;
      ignoreShellProgramCheck = true;
    };
  };

  system.stateVersion = "25.11";
}

