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
  cfg = srv.seerr;
  confPath = "/run/container-secrets/seerr.env";
in
{
  options.${namespace}.services.seerr = mkServiceOptions {
    name = "seerr";
    description = "Seerr for requesting media content";
    port.number = 5055;
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.${namespace}.seerr;
    secrets.env = {
      file = "secrets/seerr.env";
      format = "dotenv";
      mountPath = confPath;
    };
    resources = {
      CPUQuota = "400%";
      MemoryMax = "1024M";
      TasksMax = 512;
    };
    environment = {
      PORT = toString cfg.port.number;
      HOST = "0.0.0.0";
      NODE_ENV = "production";
      LOG_LEVEL = "info";
      # This should be stored on a persistent migratable volume!
      CONFIG_DIRECTORY = "/var/lib/seerr";
    };
    serviceConfig = {
      EnvironmentFile = confPath;
      StateDirectory = "seerr";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/seerr";
    };
  });
}
