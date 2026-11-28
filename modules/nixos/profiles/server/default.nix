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
  cfg = config.${namespace}.profiles.server;
in
{
  options.${namespace}.profiles.server.enable = mkEnableOption "headless application host";

  config = mkIf cfg.enable {
    homelab = {
      profiles.base = enabled;
      secrets = enabled;
      system.remoteRescue = enabled;
      observability.alerts = enabled;
      services.chrony = enabled;
      logging = enabled;
    };

    security.sudo.extraRules = [
      {
        users = [ "ishan" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    systemd.targets.multi-user = enabled;

    containers = mapAttrs (_name: _service: { config.nixpkgs.pkgs = pkgs; }) (
      filterAttrs (_name: service: service.enable) config.system.homelab.registry.services
    );

    # Running OCI containers inside nspawn containers triggers an error like
    # unable to create session key: disk quota exceeded
    # Gitea runners do this so I needed to increase disk quota for keyring
    boot.kernel.sysctl = {
      "kernel.keys.maxkeys" = 1000000;
      "kernel.keys.maxbytes" = 25000000;
      "net.core.rmem_max" = 134217728;
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.mptcp.enabled" = 0;
      "kernel.yama.ptrace_scope" = 2;
      "kernel.kptr_restrict" = 2;
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
      "dev.tty.ldisc_autoload" = 0;
      "net.ipv4.tcp_rfc1337" = 1;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "vm.mmap_rnd_bits" = 32;
      "vm.mmap_rnd_compat_bits" = 16;
      "vm.overcommit_memory" = mkIf (any (name: config.${namespace}.services.${name}.enable) [
        "authelia"
        "tracearr"
      ]) 1;
    };

    boot.kernelModules = [
      "tcp_bbr"
      "wireguard"
    ];

    boot.kernelParams = [ "slab_nomerge" ];

    security.protectKernelImage = true;

    sops.secrets.ishan-password = {
      sopsFile = repoFile "secrets/users/ishan-password";
      format = "binary";
      neededForUsers = true;
    };

    sops.secrets.atuin-sync-address = {
      sopsFile = repoFile "secrets/atuin/sync-address";
      format = "binary";
      owner = "ishan";
    };

    programs.fish.interactiveShellInit = ''
      test -r ${config.sops.secrets.atuin-sync-address.path}; and set -gx ATUIN_SYNC_ADDRESS (cat ${config.sops.secrets.atuin-sync-address.path})
    '';
    programs.bash.interactiveShellInit = ''
      [ -r ${config.sops.secrets.atuin-sync-address.path} ] && export ATUIN_SYNC_ADDRESS="$(cat ${config.sops.secrets.atuin-sync-address.path})"
    '';

    users = {
      mutableUsers = false;
      users.ishan = {
        uid = 1000;
        extraGroups = [ "wheel" ];
        group = "users";
        createHome = true;
        home = "/home/ishan";
        homeMode = "700";
        useDefaultShell = true;
        isNormalUser = true;
        linger = true;
        hashedPasswordFile = config.sops.secrets.ishan-password.path;
      };
    };

    environment.systemPackages = with pkgs; [
      bashInteractive
      btop
      coreutils
      curl
      dig
      e2fsprogs
      fd
      file
      findutils
      fish
      git
      htop
      iftop
      inetutils
      iotop
      iproute2
      iperf3
      iptraf-ng
      iputils
      jq
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
