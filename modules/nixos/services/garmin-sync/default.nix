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
  cfg = config.${namespace}.services.garmin-sync;
  package = pkgs.${namespace}.garmin;
  envPath = "/run/container-secrets/garmin.env";
  tokenDir = "/run/container-secrets/garmin-tokens";
in
{
  options.${namespace}.services.garmin-sync = mkServiceOptions {
    name = "garmin-sync";
    description = "Weekly Garmin Connect to Postgres sync";
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets = {
      env = {
        file = "secrets/garmin/garmin.env";
        format = "dotenv";
        mountPath = envPath;
      };
      oauth1-token = {
        file = "secrets/garmin/oauth1_token";
        format = "binary";
        mountPath = "${tokenDir}/oauth1_token.json";
      };
      oauth2-token = {
        file = "secrets/garmin/oauth2_token";
        format = "binary";
        mountPath = "${tokenDir}/oauth2_token.json";
      };
    };
    containerConfig = {
      environment.systemPackages = [ package ];

      systemd.services.garmin-sync = {
        inherit (cfg) description;
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          package
          pkgs.coreutils
        ];
        environment.GARMIN_TOKEN_DIR = tokenDir;
        script = ''
          garmin-pg db init
          garmin-pg sync --end-date "$(date -d 'last saturday' +%F)"
        '';
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = envPath;
          User = cfg.runtimeUser.name;
          Group = cfg.runtimeUser.group;
        };
      };

      systemd.timers.garmin-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Sun *-*-* 04:15:00";
          Persistent = true;
        };
      };
    };
  });
}
