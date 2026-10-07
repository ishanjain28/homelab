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
  settingsPath = "/run/container-secrets/seerr.json";
in
{
  options.${namespace}.services.seerr = mkServiceOptions {
    name = "seerr";
    description = "Seerr for requesting media content";
    endpoints.web.port = 5055;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/api/v1/status";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    serviceProfile = "jit";
    package = pkgs.${namespace}.seerr;
    secrets.env = {
      file = "secrets/seerr/vars.env";
      format = "dotenv";
      mountPath = confPath;
    };
    secrets.settings = {
      file = "secrets/seerr/config.json";
      format = "json";
      key = "";
      mountPath = settingsPath;
    };
    resources = {
      CPUQuota = "400%";
      MemoryMax = "1024M";
      TasksMax = 512;
    };
    environment = {
      PORT = toString cfg.endpoints.web.port;
      HOST = "0.0.0.0";
      NODE_ENV = "production";
      LOG_LEVEL = "info";
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
