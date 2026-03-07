{
  config,
  pkgs,
  lib,
  inputs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.desktop.stylix;
in
{
  options.${namespace}.desktop.stylix = {
    enable = mkEnableOption "Stylix profile for desktop machines";
  };

  config = mkIf cfg.enable {
    stylix = enabled // {
      autoEnable = false;
      homeManagerIntegration.followSystem = true;
      image = pkgs.fetchurl {
        url = "https://w.wallhaven.cc/full/p9/wallhaven-p9qpyp.jpg";
        sha256 = "sha256-GeB4yYgmgbkQ82wQv4g+jh+Mh4UNJHK0y4/JPY2HeiU=";
      };
      base16Scheme = "${inputs.base16-schemes.outPath}/base16/catppuccin-mocha.yaml";
      cursor = {
        package = pkgs.rose-pine-cursor;
        name = "BreezeX-RosePine-Linux";
        size = 28;
      };
      fonts = {
        emoji = {
          name = "Noto Color Emoji";
          package = pkgs.noto-fonts-color-emoji;
        };
        sansSerif = {
          name = "Roboto Regular";
          package = pkgs.roboto;
        };
        serif = {
          name = "Roboto Serif 20pt Regular";
          package = pkgs.roboto-serif;
        };
        sizes = {
          applications = 12;
          terminal = 10;
        };
      };
      polarity = "dark";
      targets = {
        chromium = enabled;
        nixos-icons = enabled;
      };
    };

    snowfallorg.users.ishan.home.config = {
      stylix.targets = {
        alacritty = enabled;
      };
    };
  };
}
