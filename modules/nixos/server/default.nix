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
      system.remoteRescue = enabled;

      services = {
        chrony = enabled;
      };
    };

    environment.systemPackages = with pkgs; [
      bashInteractive
      bind
      btop
      coreutils
      curl
      dig
      dnsutils
      e2fsprogs
      fd
      file
      findutils
      fish
      git
      htop
      inetutils
      iotop
      iproute2
      iperf3
      iputils
      jq
      kitty.terminfo
      lm_sensors
      lsof
      lvm2
      mediainfo
      mtr
      netcat-openbsd
      ncdu
      neovim
      nmap
      nvme-cli
      openssl
      pciutils
      pkg-config
      procps
      psmisc
      ripgrep
      rsync
      smartmontools
      strace
      sysstat
      tcpdump
      traceroute
      tree
      usbutils
      util-linux
      wget
    ];
  };
}
