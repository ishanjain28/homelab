{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hardware.networking;
in
{
  options.${namespace}.hardware.networking = with types; {
    enable = mkBoolOpt false "Whether or not to enable networking support";
    domain = mkOpt str "" "The domain name of the machine";
    hostName = mkOpt str "nixos" "The hostname of the machine";
    hosts = mkOpt attrs { } (mdDoc "An attribute set to merge with `networking.hosts`");
    tcpPorts = mkOpt (listOf port) [ 80 443 8080 ] "A list of ports to open in the firewall";
    vlans = mkOpt attrs { } (msDoc "List of VLAN interfaces to configure");
    links = mkOpt attrs { } (msDoc "List of PHY links to configure");
    interfaces = mkOpt attrs { } (msDoc "List of interfaces to configure");

    networks = mkOpt attrs { } (msDoc "List of networks devices to configure");
    netdevs = mkOpt attrs { } (msDoc "List of virtual network devices to configure");
  };

  config = mkIf cfg.enable {
    # WiFi is not used on any device.
    # TODO: make this option configurable for each system.
    systemd.services.wpa_supplicant = disabled;

    # TODO: Change this to use networkmanager for desktop
    # and continue using systemd-networkd for servers.
    networking.networkmanager = disabled // {
      # TODO: make this configurable by machine
      unmanaged = [ "type:wifi" ];
    };

    # Enable debug logs
    # systemd.services."systemd-networkd".environment.SYSTEMD_LOG_LEVEL = "debug";

    systemd.network = enabled // {
      # To have predictable names for network interfaces
      inherit (cfg) links;
      inherit (cfg) networks;
      inherit (cfg) netdevs;
    };

    networking = {
      inherit (cfg) domain;
      inherit (cfg) hosts;
      inherit (cfg) vlans;
      inherit (cfg) interfaces;

      hostId = lib.mkDefault (
        builtins.substring 0 8 (builtins.hashString "sha256" config.networking.hostName)
      );

      hostName = mkDefault cfg.hostName;
      useDHCP = mkDefault false;

      # Enable networking
      nftables = enabled;

      firewall = enabled // {
        allowPing = true;
        allowedTCPPorts = cfg.tcpPorts;
      };
    };
  };
}
