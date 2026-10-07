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
  cfg = srv.telegraf-snmp;
  metrics = config.${namespace}.metrics;
  mibPaths = [
    "${pkgs.net-snmp.out}/share/snmp/mibs"
    "${pkgs.${namespace}.mikrotik-mib}/share/snmp/mibs"
  ];
in
{
  options.${namespace}.services.telegraf-snmp =
    mkServiceOptions {
      name = "telegraf-snmp";
      description = "Telegraf SNMP poller";
    }
    // {
      interval = mkOpt types.nonEmptyStr "30s" "Polling and flush interval.";
    };

  config = mkIf cfg.enable (mkMerge [
    # nspawn only admits the @memlock syscalls when the container holds
    # CAP_IPC_LOCK; telegraf mlocks the memory holding its secrets (the
    # output token) and deadlocks in memguard when mlock is refused.
    { containers.${cfg.name}.additionalCapabilities = [ "CAP_IPC_LOCK" ]; }

    (mkServiceContainer {
      service = cfg;
      serviceProfiles.telegraf = "raw-sockets";
      containerTimeout = "2min";

      resources = {
        CPUQuota = "50%";
        MemoryMax = "256M";
        TasksMax = 256;
      };

      containerConfig = {
        services.telegraf = enabled // {
          extraConfig = {
            agent = {
              inherit (cfg) interval;
              flush_interval = cfg.interval;
              round_interval = true;
              omit_hostname = true;
              snmp_translator = "gosmi";
            };

            inputs.snmp = map (input: { path = mibPaths; } // input) (import ./inputs.nix);

            outputs.influxdb_v2 = [
              {
                urls = [ metrics.victoriaMetricsUrl ];
                bucket = "telegraf";
                organization = "homelab";
                token = "";
              }
            ];
          };
        };

        systemd.services.telegraf.serviceConfig = {
          User = mkForce cfg.runtimeUser.name;
          Group = mkForce cfg.runtimeUser.group;
          AmbientCapabilities = mkForce [ ];
        };
      };
    })
  ]);
}
