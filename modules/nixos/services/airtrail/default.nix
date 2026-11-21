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
  cfg = srv.airtrail;
  package = pkgs.${namespace}.airtrail;
  envPath = "/run/container-secrets/airtrail.env";
in
{
  options.${namespace}.services.airtrail = mkServiceOptions {
    name = "airtrail";
    description = "AirTrail flight tracker";
    endpoints.web.port = 3000;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/api/ping";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    serviceProfile = "jit";
    inherit package;
    secrets.env = {
      file = "secrets/airtrail.env";
      format = "dotenv";
      mountPath = envPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1024M";
      TasksMax = 512;
    };
    environment = {
      HOST = "::";
      PORT = toString cfg.networking.endpoints.web.port;
      UPLOAD_LOCATION = "/var/lib/airtrail";
      ADDRESS_HEADER = "X-Forwarded-For";
      BODY_SIZE_LIMIT = "20M";
      NODE_ENV = "production";
    };
    serviceConfig = {
      EnvironmentFile = envPath;
      ExecStartPre = getExe' package "airtrail-migrate";
      StateDirectory = "airtrail";
      StateDirectoryMode = "0700";
    };
  });
}
