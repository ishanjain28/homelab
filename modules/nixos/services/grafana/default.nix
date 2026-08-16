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
  cfg = srv.grafana;
  grafanaConfigPath = "/run/container-secrets/grafana.ini";
  ldapConfigPath = "/run/container-secrets/ldap.toml";
in
{
  options.${namespace}.services.grafana = mkServiceOptions {
    name = "grafana";
    port = 3000;
    monitor = {
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    name = "grafana";
    description = "Grafana dashboard service";
    inherit (cfg) vlan;
    ports = [ cfg.port ];
    package = pkgs.grafana;
    exec = "/bin/grafana server -homepath ${pkgs.grafana}/share/grafana -config ${grafanaConfigPath}";

    secrets = {
      config = {
        name = "grafana-ini";
        file = "secrets/grafana/grafana.ini";
        format = "binary";
        mountPath = grafanaConfigPath;
      };
      ldap = {
        name = "grafana-ldap";
        file = "secrets/grafana/ldap.toml";
        format = "binary";
        mountPath = ldapConfigPath;
      };
    };

    resources = {
      CPUQuota = "400%";
      MemoryMax = "1G";
      TasksMax = 512;
    };

    environment = {
      GF_PATHS_DATA = "/var/lib/grafana";
      GF_PATHS_LOGS = "/var/log/grafana";
      GF_PATHS_PLUGINS = "/var/lib/grafana/plugins";
      GF_PATHS_PROVISIONING = "/var/lib/grafana/provisioning";
      GF_AUTH_LDAP_CONFIG_FILE = ldapConfigPath;
      GF_SERVER_HTTP_ADDR = "0.0.0.0";
      GF_SERVER_HTTP_PORT = toString cfg.port;
    };

    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/install -d /var/lib/grafana/plugins /var/lib/grafana/provisioning/dashboards /var/lib/grafana/provisioning/datasources /var/lib/grafana/provisioning/plugins /var/lib/grafana/provisioning/alerting";
      Restart = "always";
      RestartSec = "5s";
      RuntimeDirectory = "grafana";
      StateDirectory = "grafana";
      LogsDirectory = "grafana";
      WorkingDirectory = "/var/lib/grafana";
    };
  });
}
