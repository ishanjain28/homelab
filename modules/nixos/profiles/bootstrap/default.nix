{
  config,
  inputs,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.profiles.bootstrap;
  bootstrapKeys = filter (key: key != "") (map trim (splitString "\n" (builtins.readFile "${inputs.self}/ssh-keys.txt")));
in
{
  options.${namespace}.profiles.bootstrap.enable = mkEnableOption "remote installation and rescue environment";

  config = mkIf cfg.enable {
    homelab.profiles.base = enabled;

    networking = {
      hostName = mkDefault "nixos-bootstrap";
      useDHCP = mkForce false;
      firewall = {
        allowedTCPPorts = [ 22 ];
        allowedUDPPorts = [ 5353 ];
      };
    };

    systemd.network = enabled // {
      wait-online.anyInterface = true;
      networks."10-bootstrap-dhcp" = {
        matchConfig.Name = [
          "en*"
          "eth*"
        ];
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
    };

    services.openssh = enabled // {
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
        KbdInteractiveAuthentication = false;
      };
    };

    services.avahi = enabled // {
      nssmdns4 = true;
      openFirewall = true;
    };

    services.lldpd = enabled;

    users.users.root.openssh.authorizedKeys.keys = bootstrapKeys;
    users.users.ishan = {
      group = "users";
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = bootstrapKeys;
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

    environment.systemPackages = with pkgs; [
      age
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
      nano
      ncdu
      neovim
      netcat-openbsd
      nix
      nix-output-monitor
      nixos-anywhere
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
