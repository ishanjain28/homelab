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
  cfg = srv.bulwark;
  stateDir = "/var/lib/bulwark";
  envPath = "/run/container-secrets/bulwark.env";
in
{
  options.${namespace}.services.bulwark = mkServiceOptions {
    name = "bulwark";
    description = "Bulwark webmail";
    endpoints.web.port = 3000;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.bulwark;
    serviceProfile = "jit";
    secrets.env = {
      file = "secrets/bulwark.env";
      format = "dotenv";
      mountPath = envPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 256;
    };
    environment = {
      HOSTNAME = "::";
      PORT = toString cfg.endpoints.web.port;
      NEXT_TELEMETRY_DISABLED = "1";
    };
    serviceConfig = {
      EnvironmentFile = envPath;
      StateDirectory = "bulwark";
      StateDirectoryMode = "0700";
      WorkingDirectory = stateDir;
    };
  });
}
