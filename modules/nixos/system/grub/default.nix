{
  config,
  lib,
  namespace,
  ...
}:
with lib;
let
  cfg = config.${namespace}.profiles.grub;
in
{
  options.${namespace}.profiles.grub = {
    enable = mkEnableOption "Enable the GRUB bootloader";
  };

  config = mkIf cfg.enable {
    boot.loader.grub = {
      enable = mkDefault true;
      devices = [ "nodev" ];
      efiSupport = true;
      useOSProber = true;
      gfxmodeEfi = "1280x720";
      backgroundColor = "#000000";
      fontSize = 36;
      # splashImage = ../desktop/stylix/background.png;
      # font =
      #   "${pkgs.source-code-pro}/share/fonts/opentype/SourceCodePro-Medium.otf";
    };
  };
}
