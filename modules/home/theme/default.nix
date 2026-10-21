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
  cfg = config.${namespace}.theme;
in
{
  options.${namespace}.theme.enable = mkEnableOption "Stylix theming";

  config = mkIf cfg.enable {
    stylix = enabled // {
      polarity = "dark";
      base16Scheme = "${pkgs.base16-schemes}/share/themes/onedark-dark.yaml";
      fonts.monospace = {
        package = pkgs.paper-mono;
        name = "Paper Mono";
      };
      overlays = disabled;
      targets.neovim = disabled;
    };
  };
}
