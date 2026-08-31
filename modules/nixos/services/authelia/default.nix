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
  cfg = srv.authelia;
  containerConfPath = "/run/container-secrets/authelia.yml";
in
{
  options.${namespace}.services.authelia = mkServiceOptions {
    name = "authelia";
    description = "Authelia authentication and authorization server";
    port.number = 9091;
    monitor = enabled // {
      port = cfg.port.number;
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      homelab.services.authelia.runtimeUser = {
        name = mkDefault "authelia-main";
        group = mkDefault "authelia-main";
      };
    }

    (mkServiceContainer {
      service = cfg;
      secrets = {
        conf = {
          file = "secrets/authelia.yml";
          format = "yaml";
          mountPath = containerConfPath;
        };
      };
      resources = {
        CPUQuota = "400%";
        MemoryMax = "2G";
        TasksMax = 256;
      };

      containerConfig = {
        services.authelia.instances.main = enabled // {
          package = pkgs.authelia;
          settingsFiles = [ containerConfPath ];
          secrets.manual = true;
          environmentVariables = {
            AUTHELIA_SERVER_ADDRESS = "tcp://0.0.0.0:${toString cfg.port.number}";
          };
        };

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
    })
  ]);
}
