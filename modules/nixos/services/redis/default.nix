{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.redis;
  containerPasswordPath = "/run/container-secrets/redis-password";
in
{
  options.${namespace}.services.redis =
    mkServiceOptions {
      name = "redis";
      description = "Redis server";
      port.number = 6379;
      monitor = {
        protocol = "tcp";
      };
    }
    // (with types; {
      bind = mkOpt str "0.0.0.0" "Redis bind address inside the container.";
      maxmemory = mkOpt str "256mb" "Redis maxmemory setting.";
    });

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;

    secrets.password = {
      file = "secrets/redis/password";
      format = "binary";
      mountPath = containerPasswordPath;
    };

    resources = {
      CPUQuota = "100%";
      MemoryMax = "512M";
      TasksMax = 256;
    };

    containerConfig = {
      services.redis.servers."" = {
        enable = true;
        inherit (cfg) bind;
        port = cfg.port.number;
        openFirewall = true;
        requirePassFile = containerPasswordPath;

        settings = {
          protected-mode = "yes";
          inherit (cfg) maxmemory;
          maxmemory-policy = "allkeys-lru";
          appendonly = "no";
        };
      };
    };
  });
}
