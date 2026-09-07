{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  inherit (lib)
    filterAttrs
    mapAttrs
    mapAttrsToList
    mkAfter
    mkMerge
    ;

  registry = config.system.homelab.registry;
  allServices = registry.services;
  enabledServices = filterAttrs (_name: service: service.enable) allServices;
  logging = config.${namespace}.logging;
  loggedServices = filterAttrs (_name: service: service.enable && service.logging.enable) allServices;
  gatus = config.${namespace}.services.gatus;

  alloyConfig = name: ''
    logging {
      level = "warn"
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        regex         = "([a-zA-Z0-9_.@-]+\\.service)"
        target_label  = "unit"
      }

      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "priority"
      }

      rule {
        action = "labeldrop"
        regex  = "syslog_identifier|job|service_name"
      }
    }

    loki.source.journal "systemd" {
      forward_to    = [loki.write.local.receiver]
      relabel_rules = loki.relabel.journal.rules
      labels        = {container = "${name}", source = "journald"}
      max_age       = "24h"
    }

    loki.write "local" {
      endpoint {
        url = "${logging.lokiPushUrl}"
      }
    }
  '';

  serviceEndpoints = mapAttrsToList (
    serviceName: srv:
    let
      inherit (srv) monitor;
      inherit (monitor)
        endpoint
        group
        protocol
        path
        conditions
        ;
      inherit (monitor) name;
      domain = config.${namespace}.hardware.networking.domain;
      defaultAddress = if domain != "" then "${serviceName}.${domain}" else serviceName;
      address = if monitor.address != "" then monitor.address else defaultAddress;
      port = srv.endpoints.${endpoint}.port;
      url =
        if protocol == "http" || protocol == "https" then
          "${protocol}://${address}:${toString port}${path}"
        else
          "${protocol}://${address}:${toString port}";
    in
    {
      inherit name group url;
      inherit (monitor) interval;
      inherit conditions;
    }
  ) (filterAttrs (_name: srv: (srv ? monitor) && srv.monitor.enable) enabledServices);

  invalidMonitorEndpoints =
    mapAttrsToList (serviceName: srv: "${serviceName}:${toString srv.monitor.endpoint}")
      (
        filterAttrs (
          _name: srv:
          srv.monitor.enable
          && (srv.monitor.endpoint == null || !(hasAttr srv.monitor.endpoint srv.endpoints))
        ) enabledServices
      );

  gatusSettings.endpoints = serviceEndpoints ++ gatus.externalEndpoints;
in
{
  options.${namespace}.logging = {
    enable = mkBoolOpt false "Whether to collect homelab logs with Alloy and push them to Loki.";
    lokiPushUrl = mkOption {
      type = types.str;
      description = "Loki push API URL used by Alloy.";
    };
  };

  config = mkMerge [
    {
      assertions = [
        {
          assertion = invalidMonitorEndpoints == [ ];
          message = "Monitored services reference missing endpoints: ${concatStringsSep ", " invalidMonitorEndpoints}";
        }
      ];
    }

    (mkIf logging.enable {
      services.alloy = enabled // {
        extraFlags = [
          "--disable-reporting"
          "--server.http.enable-pprof=false"
        ];
      };

      systemd.services.alloy.serviceConfig.SupplementaryGroups = mkAfter [ "adm" ];

      environment.etc."alloy/config.alloy".text = alloyConfig "host";

      containers = mapAttrs (name: _service: {
        config = {
          services.alloy = enabled // {
            extraFlags = [
              "--disable-reporting"
              "--server.http.enable-pprof=false"
            ];
          };

          systemd.services.alloy.serviceConfig.SupplementaryGroups = mkAfter [
            "adm"
            "systemd-journal"
          ];

          environment.etc."alloy/config.alloy".text = alloyConfig name;
        };
      }) loggedServices;
    })

    {
      # Gatus runs in its dedicated nspawn container, never directly on the host.
      services.gatus = disabled // {
        settings = gatusSettings;
      };
    }
  ];
}
