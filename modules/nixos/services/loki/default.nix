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
  cfg = srv.loki;
in
{
  options.${namespace}.services.loki = mkServiceOptions {
    name = "loki";
    description = "Loki log storage";
    port.number = 3100;
    monitor = enabled // {
      protocol = "http";
      path = "/ready";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    resources = {
      CPUQuota = "400%";
      MemoryMax = "2G";
      TasksMax = 512;
    };
    containerConfig = {
      services.loki = enabled // {
        dataDir = "/var/lib/loki";
        configuration = {
          auth_enabled = false;

          server = {
            http_listen_address = "0.0.0.0";
            http_listen_port = cfg.port.number;
            grpc_listen_port = 9096;
            log_level = "warn";
          };

          common = {
            path_prefix = "/var/lib/loki";
            replication_factor = 1;
            ring.kvstore.store = "inmemory";
          };

          schema_config.configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];

          storage_config = {
            filesystem.directory = "/var/lib/loki/chunks";
            tsdb_shipper = {
              active_index_directory = "/var/lib/loki/tsdb-index";
              cache_location = "/var/lib/loki/tsdb-cache";
            };
          };

          limits_config = {
            retention_period = "8760h";
            max_query_lookback = "8760h";
            reject_old_samples = true;
            reject_old_samples_max_age = "168h";
          };

          compactor = {
            working_directory = "/var/lib/loki/compactor";
            retention_enabled = true;
            delete_request_store = "filesystem";
          };

          analytics.reporting_enabled = false;
        };
      };

      systemd.services.loki.serviceConfig = {
        StateDirectory = "loki";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/loki";
      };
    };
  });
}
