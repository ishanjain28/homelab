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
    description = "Grafana dashboard service";
    port.number = 3000;
    monitor = enabled // {
      protocol = "http";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.grafana;
    exec = "/bin/grafana server -homepath ${pkgs.grafana}/share/grafana -config ${grafanaConfigPath}";

    secrets = {
      config = {
        file = "secrets/grafana/grafana.ini";
        format = "ini";
        mountPath = grafanaConfigPath;
      };
      ldap = {
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
      GF_PATHS_PLUGINS = "/var/lib/grafana/plugins";
      GF_PATHS_PROVISIONING = "/var/lib/grafana/provisioning";
      GF_AUTH_LDAP_CONFIG_FILE = ldapConfigPath;
      GF_SERVER_HTTP_ADDR = "0.0.0.0";
      GF_SERVER_HTTP_PORT = toString cfg.port.number;
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      RuntimeDirectory = "grafana";
      StateDirectory = "grafana";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/grafana";
    };
  });
}
