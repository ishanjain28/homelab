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
    description = "Tracearr media server monitoring";
    port.number = 3000;
    monitor = {
      port = cfg.port.number;
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.${namespace}.tracearr;
    after = [
      "network-online.target"
      "redis.service"
    ];
    wants = [
      "network-online.target"
      "redis.service"
    ];
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
    };
    environment = {
      HOST = "0.0.0.0";
      PORT = toString cfg.port.number;
      NODE_ENV = "production";
      LOG_LEVEL = "info";
      REDIS_URL = "redis://127.0.0.1:6379";
    };
    serviceConfig = {
      EnvironmentFile = confPath;
      StateDirectory = "tracearr";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/tracearr";
      RestartSec = "5s";
    };
  });
}
