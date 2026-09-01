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
  cfg = config.${namespace}.system.remoteRescue;
in
{
  options.${namespace}.system.remoteRescue = {
    enable = mkEnableOption "remote rescue baseline";
  };

  config = mkIf cfg.enable {
    homelab.services.ssh = {
      enable = mkDefault true;
      addRootKeys = mkDefault true;
      passwordAuth = mkDefault false;
      permitRootLogin = mkDefault false;
    };

    homelab.services.tailscale = enabled;

    boot.kernelParams = [
      "panic=30"
      "boot.panic_on_fail"
    ];

    systemd = {
      enableEmergencyMode = false;
      settings.Manager = {
        RuntimeWatchdogSec = "60s";
        RebootWatchdogSec = "10min";
      };

      services.homelab-remote-boot-ready.path = with pkgs; [
        iproute2
        systemd
      ];
    };

    environment.systemPackages = with pkgs; [
      bashInteractive
      bind
      btop
      cryptsetup
      curl
      dig
      disko
      dnsutils
      dosfstools
      e2fsprogs
      efibootmgr
      fd
      file
      findutils
      fish
      git
      gptfdisk
      htop
      inetutils
      iotop
      iperf3
      iproute2
      iputils
      jq
      lsof
      lvm2
      mdadm
      mtr
      ncdu
      neovim
      netcat-openbsd
      nix
      nix-output-monitor
      nixos-install-tools
      nmap
      nvme-cli
      openssh
      parted
      pciutils
      procps
      psmisc
      ripgrep
      rsync
      smartmontools
      sops
      strace
      sysstat
      tcpdump
      tmux
      traceroute
      tree
      usbutils
      util-linux
      wget
    ];
  };
}
