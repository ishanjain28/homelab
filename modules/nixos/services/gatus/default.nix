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
in
{
  options.${namespace}.services.gatus =
    mkServiceOptions {
      name = "gatus";
      description = "Monitoring service for homelab";
      port.number = 8080;
      monitor = {
        protocol = "http";
      };
    }
    // (with types; {
      enable = mkBoolOpt true "Whether to enable Gatus.";
      openFirewall = mkBoolOpt true "Whether to open the Gatus web UI port.";
      address = mkOpt str "0.0.0.0" "Bind address";
      defaultInterval = mkOpt str "30s" "Default interval for generated service checks.";
      externalEndpoints =
        mkOpt (listOf attrs) [ ]
          "Additional raw Gatus endpoints for cameras and infrastructure.";
    });

  config = mkIf cfg.enable (mkMerge [
    {
      services.gatus = disabled // {
        settings = {
          web = {
            inherit (cfg) address;
            port = cfg.port.number;
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
          };

          alerting = {
            telegram = {
              token = "\${TELEGRAM_BOT_TOKEN}";
              id = "\${TELEGRAM_CHAT_ID}";
            };
            pushover = {
              application-token = "\${PUSHOVER_APPLICATION_TOKEN}";
              user-key = "\${PUSHOVER_USER_KEY}";
            };
          };
        };
      };
    }

    (mkSingleServiceContainer {
      service = cfg;
      package = pkgs.gatus;
      exec = "/bin/gatus";
      hardeningProfile = "network-monitor";
      secrets.env = {
        file = "secrets/gatus.env";
        format = "dotenv";
        mountPath = containerSecretPath;
      };
      environment = {
        GATUS_CONFIG_PATH = "${config.services.gatus.configFile}";
      };
      serviceConfig = {
        Restart = "always";
        StateDirectory = "gatus";
        EnvironmentFile = containerSecretPath;
      };
    })
  ]);
}
