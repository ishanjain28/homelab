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
  cfg = srv.tracearr;
  confPath = "/run/container-secrets/tracearr.env";
in
{
  options.${namespace}.services.tracearr = mkServiceOptions {
    name = "tracearr";
    port = 3000;
    monitor = {
      inherit (cfg) port;
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    name = "tracearr";
    service = cfg;
    ports = [ cfg.port ];
    secrets.env = {
      file = "secrets/tracearr.env";
      format = "dotenv";
      mountPath = confPath;
    };
    resources = {
      CPUQuota = "400%";
      MemoryMax = "1024M";
      TasksMax = 512;
    };

    containerConfig = {
      services.redis.servers."" = enabled // {
        bind = "127.0.0.1";
        port = 6379;
        openFirewall = false;
        settings = {
          protected-mode = "yes";
          maxmemory = "256mb";
          maxmemory-policy = "allkeys-lru";
          appendonly = "no";
        };
      };

      systemd.services.tracearr = {
        description = "Tracearr media server monitoring";
        after = [
          "network-online.target"
          "redis.service"
        ];
        wants = [
          "network-online.target"
          "redis.service"
        ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          HOST = "0.0.0.0";
          PORT = toString cfg.port;
          NODE_ENV = "production";
          LOG_LEVEL = "info";
          REDIS_URL = "redis://127.0.0.1:6379";
        };
        serviceConfig = {
          ExecStart = "${pkgs.${namespace}.tracearr}/bin/tracearr";
          EnvironmentFile = confPath;
          DynamicUser = false;
          User = cfg.runtimeUser.name;
          Group = cfg.runtimeUser.group;
          StateDirectory = "tracearr";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/tracearr";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    };
  });
}
