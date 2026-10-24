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
  alertingEnvPath = "/run/container-secrets/grafana-alerting.env";
  datasources = (pkgs.formats.yaml { }).generate "grafana-datasources.yaml" {
    apiVersion = 1;
    datasources = [
      {
        name = "homelab-victorialogs";
        uid = "victorialogs";
        type = "victoriametrics-logs-datasource";
        access = "proxy";
        url = "http://[${mkIpv6Address "victorialogs" 50}]:9428";
      }
      {
        name = "homelab-victoriametrics";
        uid = "efyik59h6cbnkc";
        type = "victoriametrics-metrics-datasource";
        access = "proxy";
        url = "http://[${mkIpv6Address "victoriametrics" 50}]:8428";
      }
      {
        name = "ASN names";
        uid = "asn-names";
        type = "yesoreyeram-infinity-datasource";
        access = "proxy";
        jsonData.allowedHosts = [ "https://raw.githubusercontent.com" ];
      }
    ];
  };
  provisioning = pkgs.linkFarm "grafana-provisioning" {
    "dashboards/homelab.yaml" = ./dashboards.yaml;
    "alerting/homelab.yaml" = ./alerting.yaml;
    "datasources/homelab.yaml" = datasources;
  };
in
{
  options.${namespace}.services.grafana = mkServiceOptions {
    name = "grafana";
    description = "Grafana dashboard service";
    endpoints.web.port = 3000;
    monitor = enabled // {
      endpoint = "web";
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
      alerting = {
        file = "secrets/grafana/alerting.env";
        format = "dotenv";
        mountPath = alertingEnvPath;
      };
    };

    containerConfig.environment.etc."grafana/dashboards".source = ../../../../dashboards;

    resources = {
      CPUQuota = "500%";
      MemoryMax = "3G";
      TasksMax = 512;
    };

    environment = {
      GF_PATHS_DATA = "/var/lib/grafana";
      GF_PATHS_PLUGINS = "/var/lib/grafana/plugins";
      GF_PATHS_PROVISIONING = "${provisioning}";
      GF_PLUGINS_PREINSTALL_SYNC = "victoriametrics-logs-datasource,victoriametrics-metrics-datasource,yesoreyeram-infinity-datasource";
      GF_AUTH_LDAP_CONFIG_FILE = ldapConfigPath;
      GF_SERVER_HTTP_ADDR = "0.0.0.0";
      GF_SERVER_HTTP_PORT = toString cfg.endpoints.web.port;
    };

    serviceConfig = {
      EnvironmentFile = alertingEnvPath;
      RuntimeDirectory = "grafana";
      StateDirectory = "grafana";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/grafana";
    };
  });
}
