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
  cfg = srv.mathesar;
  containerEnvPath = "/run/container-secrets/mathesar.env";
in
{
  options.${namespace}.services.mathesar = mkServiceOptions {
    name = "mathesar";
    description = "Web viewer for databases";
    endpoints.web.port = 5001;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.${namespace}.mathesar;
    exec = "/bin/mathesar run --no-venv --port ${toString cfg.endpoints.web.port}";

    secrets.env = {
      file = "secrets/mathesar.env";
      format = "dotenv";
      mountPath = containerEnvPath;
    };

    resources = {
      CPUQuota = "200%";
      MemoryMax = "2G";
      TasksMax = 512;
    };

    environment = {
      HOME = "/var/lib/mathesar";
      MEDIA_ROOT = "/var/lib/mathesar/media";
      SKIP_STATIC_COLLECTION = "true";
      HOST = "0.0.0.0";
      PORT = toString cfg.endpoints.web.port;
    };

    serviceConfig = {
      EnvironmentFile = containerEnvPath;
      ExecStartPre = "${pkgs.${namespace}.mathesar}/bin/mathesar-setup-django";
      Restart = "on-failure";
      RestartSec = "5s";
      StateDirectory = "mathesar";
      WorkingDirectory = "/var/lib/mathesar";
    };
  });
}
