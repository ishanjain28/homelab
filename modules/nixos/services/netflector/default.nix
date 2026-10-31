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
  cfg = config.${namespace}.services.netflector;
  configPath = "/run/container-secrets/netflector.toml";
in
{
  options.${namespace}.services.netflector = mkServiceOptions {
    name = "netflector";
    description = "SSDP and Samba WS-Discovery across VLANs";
    endpoints = {
      ssdp = {
        port = 1900;
        transport = "udp";
      };
      wsd = {
        port = 3702;
        transport = "udp";
      };
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.${namespace}.netflector;
    command = "${lib.getExe pkgs.${namespace}.netflector} ${configPath}";
    serviceProfile = "link-layer";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    secrets.config = {
      file = "secrets/netflector.toml";
      format = "binary";
      mountPath = configPath;
    };
    resources = {
      CPUQuota = "50%";
      MemoryMax = "128M";
      TasksMax = 128;
    };
    containerConfig.networking.firewall.interfaces =
      genAttrs (map (vlan: "eth${toString vlan}") (remove 50 cfg.vlans))
        (_: {
          allowedTCPPortRanges = [
            {
              from = 32768;
              to = 60999;
            }
          ];
        });
  });
}
