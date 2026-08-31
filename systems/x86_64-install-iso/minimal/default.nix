{
  lib,
  pkgs,
  namespace,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  bootstrapKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAX88KLYCUWS1IKTGsgIRIHwGxTyfhsiRyAgtv65GEEm ishan@turquoise"
  ];
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # `install-iso` adds wireless support that
  # is incompatible with networkmanager.
  networking.wireless.enable = mkForce false;

  networking = {
    hostName = mkForce "nixos-bootstrap";
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

  users = {
    defaultUserShell = pkgs.fish;
    users.ishan = {
      group = "users";
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = bootstrapKeys;
    };
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

  nix = mkNixConfig { inherit lib pkgs; };

  programs.fish = enabled;

  environment.systemPackages = with pkgs; [
    age
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

  environment.shells = with pkgs; [
    bashInteractive
    fish
  ];

  documentation.man = enabled;

  system.stateVersion = "26.05";
}
