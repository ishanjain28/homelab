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
  serviceName = "alloy-syslog";
  srv = config.${namespace}.services;
  logging = config.${namespace}.logging;
  cfg = srv.alloy-syslog;
in
{
  options.${namespace}.services.alloy-syslog = mkServiceOptions {
    name = serviceName;
    description = "Alloy syslog receiver";
    port = 514; # Primary listening port
    monitor = {
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.grafana-alloy;
    exec = "/bin/alloy run /etc/alloy-syslog --disable-reporting --server.http.listen-addr=127.0.0.1:0 --server.http.enable-pprof=false";
    resources = {
      CPUQuota = "100%";
      MemoryMax = "256M";
      TasksMax = 256;
    };

    serviceConfig = {
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
      StateDirectory = serviceName;
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/${serviceName}";
    };
    containerConfig = {
      networking.firewall.allowedUDPPorts = [ cfg.port ];

      environment.etc."alloy-syslog/config.alloy".text = ''
        logging {
          level = "warn"
        }

        loki.relabel "syslog" {
          forward_to = []

          rule {
            source_labels = ["__syslog_message_hostname"]
            target_label  = "device"
          }

          rule {
            source_labels = ["__syslog_message_severity"]
            target_label  = "priority"
          }

          rule {
            source_labels = ["__syslog_message_app_name"]
            target_label  = "app"
          }

          rule {
            source_labels = ["__syslog_message_facility"]
            target_label  = "facility"
          }

          rule {
            source_labels = ["__syslog_connection_hostname"]
            target_label  = "connection_hostname"
          }
        }

        loki.source.syslog "syslog" {
          listener {
            address             = "0.0.0.0:514"
            protocol            = "tcp"
            syslog_format       = "rfc3164"
            use_incoming_timestamp = true
            rfc3164_default_to_current_year = true
            labels              = { source = "syslog", protocol = "tcp" }
          }
          listener {
            address             = "0.0.0.0:514"
            protocol            = "udp"
            syslog_format       = "rfc3164"
            use_incoming_timestamp = true
            rfc3164_default_to_current_year = true
            labels              = { source = "syslog", protocol = "udp" }
          }
          forward_to    = [loki.write.syslog.receiver]
          relabel_rules = loki.relabel.syslog.rules
        }

        loki.write "syslog" {
          endpoint {
            url = "${logging.lokiPushUrl}"
          }
        }
      '';
    };
  });
}
