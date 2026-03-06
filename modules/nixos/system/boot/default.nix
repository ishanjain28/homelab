{ config, pkgs, namespace, lib, ... }:
with lib;
with lib.${namespace};
let cfg = config.${namespace}.system.boot;
in {
  options.${namespace}.system.boot = with types; {
    enable = mkBoolOpt false "Whether or not to enable booting";
    timeout = mkOpt types.int 60 "Timeout for the bootloader";
    secure = {
      enable = mkBoolOpt false "Enable Secure Boot";
      pkiBundle =
        mkOpt types.str "/etc/secureboot" "The path to the PKI bundle";
    };
  };

  config = mkIf cfg.enable {
    boot = {
      initrd.systemd = enabled;

      # Use latest kernel by default.
      kernelPackages = mkDefault pkgs.linuxPackages_latest;

      # Secure Boot
      lanzaboote = {
        inherit (cfg.secure) enable;
        inherit (cfg.secure) pkiBundle;
      };

      # Bootloader
      loader = {
        efi = {
          efiSysMountPoint = "/boot";
          # Set to true only the first time
          canTouchEfiVariables = true;
        };

        systemd-boot.enable = mkForce (!cfg.secure.enable);
        timeout = mkDefault cfg.timeout;
      };
    };
  };
}

