{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.profiles.desktop;
in
{
  options.${namespace}.profiles.desktop.enable = mkEnableOption "graphical workstation";

  config = mkIf cfg.enable {
    homelab.profiles.base = enabled;

    fonts.packages = with pkgs; [
      cabin
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      unifont
    ];
  };
}
