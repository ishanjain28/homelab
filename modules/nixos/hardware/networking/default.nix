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
    extra = mkBoolOpt true "Whether or not to enable extra networking features";
    tcpPorts = mkOpt (listOf port) [ 80 443 8080 ] "A list of ports to open in the firewall";
    vlans = mkOpt attrs { } (msDoc "List of VLAN interfaces to configure");
    interfaces = mkOpt attrs { } (msDoc "List of interfaces to configure");
  };

  config = mkIf cfg.enable {
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
      networkmanager.enable = cfg.extra;
      nftables.enable = cfg.extra;

      firewall = enabled // {
        allowPing = true;
        allowedTCPPorts = cfg.tcpPorts;
      };
    };
  };
}
