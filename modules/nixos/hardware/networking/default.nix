{ config, lib, namespace, ... }:
with lib;
with lib.${namespace};
let cfg = config.${namespace}.hardware.networking;
in {
  options.${namespace}.hardware.networking = with types; {
    enable = mkBoolOpt false "Whether or not to enable networking support";
    domain = mkOpt str "" "The domain name of the machine";
    hostName = mkOpt str "nixos" "The hostname of the machine";
    hosts = mkOpt attrs { }
      (mdDoc "An attribute set to merge with `networking.hosts`");
    extra = mkBoolOpt true "Whether or not to enable extra networking features";
    tcpPorts = mkOpt (listOf port) [ 80 443 8080 ]
      "A list of ports to open in the firewall";
  };

  config = mkIf cfg.enable {
    networking = {
      inherit (cfg) domain;
      inherit (cfg) hosts;
      hostName = mkDefault cfg.hostName;

      # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
      # (the default) this is the recommended approach. When using systemd-networkd it's
      # still possible to use this option, but it's recommended to use it in conjunction
      # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
      interfaces.wlan0.useDHCP = mkDefault true;
      useDHCP = mkDefault true;

      # Enable networking
      networkmanager.enable = cfg.extra;
      nftables.enable = cfg.extra;

      firewall = enabled // {
        allowPing = true;
        allowedTCPPorts = cfg.tcpPorts;
      };
    };
  };
}
