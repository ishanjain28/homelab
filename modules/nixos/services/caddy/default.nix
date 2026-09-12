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
  srv = config.${namespace}.services;
  cfg = srv.caddy;
  configPath = "/run/container-secrets/caddy.json";
in
{
  options.${namespace}.services.caddy =
    mkServiceOptions {
      name = "caddy";
      description = "Caddy ingress proxy";
      endpoints = {
        http.port = 80;
        https.port = 443;
        admin = {
          port = 2019;
          expose = false;
        };
      };
      monitor = enabled // {
        endpoint = "https";
        protocol = "tcp";
      };
    }
    // {
      configFile = mkOpt types.str "" "Repository-relative path to the encrypted Caddy JSON file.";
    };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.configFile != "";
          message = "The Caddy service requires configFile.";
        }
      ];
    }

    (mkSingleServiceContainer {
      service = cfg;
      command = "${pkgs.${namespace}.caddy}/bin/caddy run --config ${configPath}";

      secrets.config = {
        file = cfg.configFile;
        format = "json";
        mountPath = configPath;
      };

      environment.XDG_DATA_HOME = "/var/lib";

      resources = {
        CPUQuota = "400%";
        MemoryMax = "1G";
        TasksMax = 1024;
      };

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStartPre = "${pkgs.${namespace}.caddy}/bin/caddy validate --config ${configPath}";
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
        StateDirectory = "caddy";
        StateDirectoryMode = "0700";
        UMask = "0077";
      };
    })
  ]);
}
