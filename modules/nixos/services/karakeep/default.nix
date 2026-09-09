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
  cfg = srv.karakeep;
  karakeepEnv = "/run/container-secrets/karakeep.env";
  meilisearchMasterKey = "/run/container-secrets/meilisearch.key";
in
{
  options.${namespace}.services.karakeep = mkServiceOptions {
    name = "karakeep";
    description = "Karakeep bookmark manager";
    endpoints.web.port = 3000;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    secrets = {
      karakeep = {
        file = "secrets/karakeep/karakeep.env";
        format = "dotenv";
        mountPath = karakeepEnv;
      };
      meilisearch = {
        file = "secrets/karakeep/meilisearch.key";
        format = "binary";
        mountPath = meilisearchMasterKey;
      };
    };
    resources = {
      CPUQuota = "400%";
      MemoryMax = "4G";
      TasksMax = 1024;
    };

    containerConfig = {
      services.karakeep = enabled // {
        package = pkgs.karakeep;
        browser = enabled;
        meilisearch = enabled;
        environmentFile = karakeepEnv;
        extraEnvironment = {
          NODE_ENV = "production";
          DATA_DIR = "/var/lib/karakeep";
          PORT = toString cfg.endpoints.web.port;
          DISABLE_NEW_RELEASE_CHECK = "true";
        };
      };

      services.meilisearch = {
        settings = {
          db_path = "/var/lib/meilisearch/data";
          dump_dir = "/var/lib/meilisearch/dumps";
          snapshot_dir = "/var/lib/meilisearch/snapshots";
          no_analytics = "true";
          env = "production";
        };

        masterKeyFile = meilisearchMasterKey;
      };

      # The NixOS Meilisearch module normally uses a dynamic user. Run it as
      # the Karakeep runtime identity so its separately mounted index volume
      # follows the same ownership model as the rest of this service.
      systemd.services.meilisearch.serviceConfig = {
        DynamicUser = mkForce false;
        User = cfg.runtimeUser.name;
        Group = cfg.runtimeUser.group;
      };
    };
  });
}
