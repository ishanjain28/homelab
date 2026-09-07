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
      services.chrony = enabled;
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

    users = {
      mutableUsers = false;
      users.ishan = {
        uid = 1000;
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        isSystemUser = false;
        group = "users";
        createHome = true;
        home = "/home/ishan";
        homeMode = "700";
        useDefaultShell = true;
        isNormalUser = true;
        hashedPassword = "$6$/4l0PEwOs7lcQlOU$rn9VlGaNJQcd.ndc.vmkIo4ZbL6uG9G3sd/mP7/AFf9ucakIfnGT4NtWllnEPnoLg5FsoHzJgpfHuDoAzNLXC/";
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
