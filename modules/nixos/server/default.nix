{ config, pkgs, lib, namespace, ... }:
with lib;
with lib.${namespace};
let cfg = config.${namespace}.server;
in {
  options.${namespace}.server = {
    enable = mkEnableOption "Profile for servers";
    extraPackages = mkOpt (types.listOf types.package) [ ]
      "Extra packages to install on servers";
  };

  config = mkIf cfg.enable {
    homelab = {
      services = { chrony = enabled; };

      virtualisation = enabled;
    };

    users.users.ishan.packages = with pkgs; [
      openssl
      pkg-config
      ripgrep
      fish
      htop
      neovim
      ncdu
      kitty.terminfo
    ];
  };
}
