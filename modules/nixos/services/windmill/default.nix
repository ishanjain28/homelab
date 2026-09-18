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
  cfg = config.${namespace}.services.windmill;
  environmentFile = "/run/container-secrets/windmill.env";
  commonEnvironment = {
    JSON_FMT = "true";
    RUST_LOG = "info";
  };
  commonServiceConfig = {
    EnvironmentFile = environmentFile;
    ExecStart = getExe pkgs.windmill;
    LimitNOFILE = 65536;
    PrivateTmp = true;
    Restart = "always";
    RestartSec = "5s";
    TimeoutStopSec = "30s";
  };
in
{
  options.${namespace}.services.windmill = mkServiceOptions {
    name = "windmill";
    description = "Windmill workflow automation platform";
    endpoints.web.port = 5678;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/api/health/status";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;

    secrets.env = {
      file = "secrets/windmill.env";
      format = "dotenv";
      mountPath = environmentFile;
    };

    resources = {
      CPUQuota = "600%";
      MemoryMax = "12G";
      TasksMax = 8192;
    };

    containerConfig.systemd.services = {
      windmill-server = {
        description = "Windmill API Server and Web UI";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = commonEnvironment // {
          MODE = "server";
          PORT = toString cfg.endpoints.web.port;
        };
        serviceConfig = commonServiceConfig // {
          User = cfg.runtimeUser.name;
          Group = cfg.runtimeUser.group;
          StateDirectory = "windmill";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/windmill";
        };
      };

      windmill-worker = {
        description = "Windmill Execution Worker";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = commonEnvironment // {
          MODE = "worker";
          DENO_TLS_CA_STORE = "system,mozilla";
        };
        serviceConfig = commonServiceConfig // {
          User = "root";
          Group = "root";
          StateDirectory = "windmill-worker";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/windmill-worker";
        };
      };
    };
  });
}
