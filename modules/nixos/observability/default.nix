{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  registry = config.system.homelab.registry;
  allServices = registry.services;
  enabledServices = filterAttrs (_name: service: service.enable) allServices;
  logging = config.${namespace}.logging;
  loggedServices = filterAttrs (_name: service: service.enable && service.logging.enable) allServices;
  gatus = config.${namespace}.services.gatus;

  serviceLokiPushUrl =
    name: service:
    let
      configuredVlans = filter (vlan: hasAttr (toString vlan) logging.lokiPushUrls) service.vlans;
    in
    if configuredVlans == [ ] then
      throw "No Loki push URL configured for ${name} on VLANs ${
        concatMapStringsSep ", " toString service.vlans
      }"
    else
      logging.lokiPushUrls.${toString (head configuredVlans)};

  hostLokiPushUrl = head (attrValues logging.lokiPushUrls);

  alloyConfig = name: lokiPushUrl: ''
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
        url = "${lokiPushUrl}"
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
    lokiPushUrls = mkOpt (types.attrsOf types.str) {
      "50" = "http://10.0.50.23:3100/loki/api/v1/push";
      "70" = "http://10.0.70.11:3100/loki/api/v1/push";
      "99" = "http://10.0.99.29:3100/loki/api/v1/push";
    } "Loki push API URLs keyed by VLAN.";
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

      environment.etc."alloy/config.alloy".text = alloyConfig "host" hostLokiPushUrl;

      containers = mapAttrs (name: service: {
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

          environment.etc."alloy/config.alloy".text = alloyConfig name (serviceLokiPushUrl name service);
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
