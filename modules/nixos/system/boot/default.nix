{
  config,
  pkgs,
  namespace,
  lib,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.system.boot;
in
{
  options.${namespace}.system.boot = with types; {
    enable = mkBoolOpt false "Whether or not to enable booting";
    timeout = mkOpt types.int 60 "Timeout for the bootloader";
    bootCounting = {
      enable = mkBoolOpt true "Enable systemd-boot automatic boot assessment.";
      tries =
        mkOpt types.ints.positive 1
          "Number of times a new generation may fail before systemd-boot skips it.";
    };
    secure = {
      enable = mkBoolOpt false "Enable Secure Boot";
      pkiBundle = mkOpt types.str "/etc/secureboot" "The path to the PKI bundle";
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
        systemd-boot.bootCounting = {
          inherit (cfg.bootCounting) enable tries;
        };
        systemd-boot.configurationLimit = mkDefault 20;
        timeout = mkDefault cfg.timeout;
      };
    };

    systemd.services = {
      homelab-remote-boot-ready = mkIf cfg.bootCounting.enable {
        description = "Verify remote access before blessing this boot";
        wantedBy = [ "boot-complete.target" ];
        requiredBy = [ "boot-complete.target" ];
        before = [ "boot-complete.target" ];
        after = [
          "network-online.target"
          "sshd.service"
        ];
        wants = [ "network-online.target" ];
        requires = [ "sshd.service" ];
        onFailure = [ "homelab-reboot-after-bad-boot.service" ];
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "2min";
        };
        script = ''
          systemctl is-active --quiet sshd.service
        '';
      };

      homelab-reboot-after-bad-boot = mkIf cfg.bootCounting.enable {
        description = "Reboot after an unblessed remote boot";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/systemctl --no-block reboot";
        };
      };
    };
  };
}
