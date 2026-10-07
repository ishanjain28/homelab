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
  cfg = config.${namespace}.services.backrest;
  stateDir = "/var/lib/backrest";
  configPath = "/run/container-secrets/backrest.json";
  rcloneConfigPath = "/run/container-secrets/rclone.conf";
in
{
  options.${namespace}.services.backrest = mkServiceOptions {
    name = "backrest";
    description = "Backrest web UI for the restic repositories";
    endpoints.web.port = 9898;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.backrest;
    secrets = {
      config = {
        file = "secrets/backrest/config.json";
        format = "json";
        key = "";
        mountPath = configPath;
      };
      rclone = {
        file = "secrets/backups/rclone.conf";
        format = "binary";
        mountPath = rcloneConfigPath;
      };
    };
    containerConfig.systemd.services.backrest.path = [ pkgs.rclone ];
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 256;
    };
    environment = {
      BACKREST_CONFIG = configPath;
      BACKREST_DATA = stateDir;
      BACKREST_PORT = ":${toString cfg.endpoints.web.port}";
      BACKREST_RESTIC_COMMAND = "${pkgs.restic}/bin/restic";
      RCLONE_CONFIG = rcloneConfigPath;
      XDG_CACHE_HOME = "${stateDir}/cache";
    };
    serviceConfig = {
      StateDirectory = "backrest";
      StateDirectoryMode = "0700";
      WorkingDirectory = stateDir;
    };
  });
}
