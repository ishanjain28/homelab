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
  cfg = srv.actual-server;
  confPath = "/run/container-secrets/actual-server.json";
in
{
  options.${namespace}.services.actual-server = mkServiceOptions {
    name = "actual-server";
    port = 5006;
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    name = "actual-server";
    description = "Actual Budget";
    service = cfg;
    ports = [ cfg.port ];
    package = pkgs.actual-server;
    exec = "/bin/actual-server";
    secrets.conf = {
      file = "secrets/actual-server.json";
      format = "json";
      mountPath = confPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1024M";
      TasksMax = 512;
    };
    environment = {
      ACTUAL_CONFIG_PATH = confPath;
      ACTUAL_DATA_DIR = "/var/lib/actual-server";
      ACTUAL_HOSTNAME = "0.0.0.0";
      ACTUAL_PORT = toString cfg.port;
      LOG_LEVEL = "info";
      NODE_ENV = "production";
    };
    serviceConfig = {
      StateDirectory = "actual-server";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/actual-server";
    };
  });
}
