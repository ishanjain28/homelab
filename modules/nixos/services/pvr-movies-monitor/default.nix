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
  containerSecretPath = "/run/container-secrets/pvr-movies-monitor.env";
in
{
  options.${namespace}.services.pvr-movies-monitor = mkServiceOptions {
    name = "pvr-movies-monitor";
    port = 3000;
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    name = "pvr-movies-monitor";
    description = "PVR Movies Monitoring Service";
    service = cfg;
    ports = [ cfg.port ];
    package = pkgs.${namespace}.pvr-movies-monitor;
    secrets.env = {
      file = "secrets/pvr-movies-monitor.env";
      format = "dotenv";
      mountPath = containerSecretPath;
    };
    resources = {
      CPUQuota = "30%";
      MemoryMax = "128M";
      TasksMax = 256;
    };
    environment = {
      HOST = "0.0.0.0";
      PORT = toString cfg.port;
      RUST_LOG = "info";
      TOKIO_WORKER_THREADS = "2";
    };
    serviceConfig = {
      EnvironmentFile = containerSecretPath;
    };
  });
}
