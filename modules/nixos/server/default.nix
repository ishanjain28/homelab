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
  };

  config = mkIf cfg.enable {
    homelab = {
      services = {
        chrony = enabled;
      };

      virtualisation = disabled;
    };

    environment.systemPackages = with pkgs; [
      bind
      fish
      htop
      iotop
      iperf3
      jq
      kitty.terminfo
      lm_sensors
      mediainfo
      mtr
      ncdu
      neovim
      nmap
      nvme-cli
      openssl
      pkg-config
      ripgrep
      rsync
      smartmontools
      tcpdump
      traceroute
      tree
    ];
  };
}
