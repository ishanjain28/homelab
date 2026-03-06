{ config, lib, namespace, ... }:
with lib;
let cfg = config.${namespace}.profiles.grub;
in {
  options.${namespace}.profiles.grub = {
    enable = mkEnableOption "Enable the GRUB bootloader";
  };

  config = {
    boot.loader.grub = {
      enable = lib.mkDefault true;
      devices = [ "nodev" ];
      efiSupport = false;
      useOSProber = true;
      gfxmodeEfi = "1280x720";
      backgroundColor = "#000000";
      fontSize = 36;
    };
  };
}
