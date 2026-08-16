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
  cfg = srv.pvr-movies-monitor;
  secret = config.sops.secrets.pvr-movies-monitor;
  containerSecretPath = "/run/container-secrets/pvr-movies-monitor.env";
in
{
  options.${namespace}.services.pvr-movies-monitor =
    mkServiceOptions {
      name = "pvr-movies-monitor";
      monitor = {
        inherit (cfg) port;
      };
    }
    // (with types; {
      host = mkOpt str "0.0.0.0" "Host";
      port = mkOpt port 3000 "Port";
    });

  config = mkIf cfg.enable (mkMerge [
    {
      sops.secrets.pvr-movies-monitor = {
        sopsFile = snowfall.fs.get-file "secrets/pvr-movies-monitor.env";
        format = "dotenv";
        mode = "0444";
        restartUnits = [ "container@pvr-movies-monitor.service" ];
      };

      containers.pvr-movies-monitor = {
        bindMounts.${containerSecretPath} = {
          hostPath = secret.path;
          isReadOnly = true;
        };
      };
    }

    (mkSingleServiceContainer {
      name = "pvr-movies-monitor";
      description = "PVR Movies Monitoring Service";
      vlan = 50;
      ports = [ cfg.port ];
      package = pkgs.${namespace}.pvr-movies-monitor;
      resources = {
        CPUQuota = "100%";
        MemoryMax = "128M";
        TasksMax = 256;
      };
      environment = {
        HOST = cfg.host;
        PORT = toString cfg.port;
        RUST_LOG = "info";
      };
      serviceConfig = {
        EnvironmentFile = containerSecretPath;
      };
    })
  ]);
}
