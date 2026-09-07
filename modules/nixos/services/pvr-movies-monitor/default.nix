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
    description = "PVR Movies Monitoring Service";
    endpoints.app.port = 3000;
    monitor = enabled // {
      endpoint = "app";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
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
      PORT = toString cfg.endpoints.app.port;
      RUST_LOG = "info";
      TOKIO_WORKER_THREADS = "2";
    };
    serviceConfig = {
      EnvironmentFile = containerSecretPath;
    };
  });
}
