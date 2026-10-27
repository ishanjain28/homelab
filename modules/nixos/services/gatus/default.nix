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
  cfg = srv.gatus;
  containerSecretPath = "/run/container-secrets/gatus.env";
  configDir = "/run/gatus";
in
{
  options.${namespace}.services.gatus =
    mkServiceOptions {
      name = "gatus";
      description = "Monitoring service for homelab";
      endpoints.web.port = 8080;
    }
    // {
      envFile = mkOption { type = types.nonEmptyStr; };
      endpointsFile = mkOption { type = types.nonEmptyStr; };
      hostChecks = mkBoolOpt false "Whether this instance pings every fleet host.";
    };

  config = mkIf cfg.enable (mkMerge [
    {
      services.gatus = {
        settings = {
          web = {
            address = "[::]";
            port = cfg.endpoints.web.port;
          };

          ui = {
            title = "Health Dashboard";
            header = "Ishan's Homelab Status";
            description = "Status of my infra in Delhi & at Home";
            logo = "https://dl.ishanjain.me/login.optimized.svg";
            default-sort-by = "name";
          };

          storage = {
            type = "postgres";
            caching = true;
            path = "\${POSTGRES_URL}";
            maximum-number-of-results = 40320;
            maximum-number-of-events = 2000;
          };

          alerting = {
            telegram = {
              token = "\${TELEGRAM_BOT_TOKEN}";
              id = "\${TELEGRAM_CHAT_ID}";
            };
            pushover = {
              application-token = "\${PUSHOVER_APPLICATION_TOKEN}";
              user-key = "\${PUSHOVER_USER_KEY}";
              default-alert = {
                description = "healthcheck failed";
                send-on-resolved = true;
                failure-threshold = 2;
                success-threshold = 2;
              };
            };
          };
        };
      };
    }

    {
      containers.gatus.bindMounts."${configDir}/config.yaml" = {
        hostPath = "${config.services.gatus.configFile}";
        isReadOnly = true;
      };
    }

    (mkSingleServiceContainer {
      service = cfg;
      package = pkgs.gatus;
      secrets = {
        env = {
          file = cfg.envFile;
          format = "dotenv";
          mountPath = containerSecretPath;
        };
        endpoints = {
          file = cfg.endpointsFile;
          format = "yaml";
          mountPath = "${configDir}/endpoints.yaml";
        };
      };
      environment = {
        GATUS_CONFIG_PATH = configDir;
      };
      serviceConfig = {
        StateDirectory = "gatus";
        EnvironmentFile = containerSecretPath;
      };
    })
  ]);
}
