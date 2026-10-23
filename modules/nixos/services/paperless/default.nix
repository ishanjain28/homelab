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
  cfg = srv.paperless;
  environmentFile = "/run/container-secrets/paperless.env";
  root = "/main/paperless";
in
{
  options.${namespace}.services.paperless = mkServiceOptions {
    name = "paperless";
    description = "Paperless-ngx document management";
    endpoints.web.port = 8000;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/accounts/login/";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    databaseUnits = [
      "paperless-web"
      "paperless-task-queue"
      "paperless-scheduler"
      "paperless-consumer"
    ];

    secrets.env = {
      file = "secrets/paperless.env";
      format = "dotenv";
      mountPath = environmentFile;
    };

    resources = {
      CPUQuota = "400%";
      MemoryMax = "4G";
      TasksMax = 1024;
    };

    containerConfig = {
      services.paperless = enabled // {
        package = pkgs.paperless-ngx;
        user = cfg.runtimeUser.name;
        address = "::";
        port = cfg.endpoints.web.port;
        dataDir = "/var/lib/paperless";
        mediaDir = "${root}/media";
        consumptionDir = "${root}/consume";
        inherit environmentFile;
        settings = {
          PAPERLESS_DBENGINE = "postgresql";
          PAPERLESS_DBNAME = cfg.database.name;
          PAPERLESS_DBUSER = cfg.database.name;
          PAPERLESS_TIME_ZONE = "Asia/Kolkata";
          PAPERLESS_OCR_LANGUAGE = "eng";
          PAPERLESS_TRASH_DIR = "${root}/trash";
          PAPERLESS_CONSUMER_RECURSIVE = true;
          PAPERLESS_ENABLE_HTTP_REMOTE_USER = true;
        };
      };

      systemd.services =
        genAttrs [ "paperless-web" "paperless-task-queue" "paperless-scheduler" "paperless-consumer" ]
          (_unit: {
            serviceConfig.ReadWritePaths = [ "${root}/trash" ];
          });
    };
  });
}
