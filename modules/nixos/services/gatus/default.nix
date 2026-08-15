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
  secret = config.sops.secrets.gatus;
in
{
  options.${namespace}.services.gatus = with types; {
    enable = mkBoolOpt true "Whether to enable Gatus.";
    openFirewall = mkBoolOpt true "Whether to open the Gatus web UI port.";
    address = mkOpt str "0.0.0.0" "Bind address";
    port = mkOpt port 8080 "Gatus web UI port.";
    defaultInterval = mkOpt str "30s" "Default interval for generated service checks.";
    externalEndpoints =
      mkOpt (listOf attrs) [ ]
        "Additional raw Gatus endpoints for cameras and infrastructure.";
  };

  config = mkIf cfg.enable (mkMerge [
    {
      sops.secrets.gatus = {
        sopsFile = snowfall.fs.get-file "secrets/gatus.env";
        format = "dotenv";
        restartUnits = [ "container@gatus.service" ];
      };

      containers.gatus = {
        bindMounts.${secret.path} = {
          hostPath = secret.path;
          isReadOnly = true;
        };
      };
    }

    {
      services.gatus = disabled // {
        settings = {
          web = {
            inherit (cfg) address;
            inherit (cfg) port;
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

    (mkNspawnService {
      name = "gatus";
      description = "Monitoring service for homelab";
      vlan = 50;
      port = [ cfg.port ];
      package = pkgs.gatus;
      exec = "/bin/gatus";
      environment = {
        GATUS_CONFIG_PATH = "${config.services.gatus.configFile}";
      };
      containerConfig = {
        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
      serviceConfig = {
        Restart = "always";
        AmbientCapabilities = "CAP_NET_RAW";
        CapabilityBoundingSet = "CAP_NET_RAW";
        NoNewPrivileges = true;
        StateDirectory = "gatus";
        EnvironmentFile = secret.path;
      };
    })
  ]);
}
