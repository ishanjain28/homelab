{
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.server;
in
{
  options.${namespace}.server = {
    enable = mkEnableOption "Profile for servers";
    extraPackages = mkOpt (types.listOf types.package) [ ] "Extra packages to install on servers";
  };

  config = mkIf cfg.enable {
    homelab = {
      services = {
        chrony = enabled;
      };

      virtualisation = disabled;
    };

    users.users.ishan.packages = with pkgs; [
      ripgrep
      fish
      htop
      neovim
      ncdu
      kitty.terminfo
    ];
  };
}
