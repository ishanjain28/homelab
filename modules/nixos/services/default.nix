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

  allServices = config.${namespace}.services or { };
  enabledServices = filterAttrs (_name: srv: srv.enable or false) allServices;
  logging = config.${namespace}.logging;
  loggedServices = filterAttrs (
    _name: service: (service.enable or false) && (service ? logging) && service.logging.enable
  ) allServices;
  gatus = allServices.gatus or { };

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
        group
        protocol
        path
        conditions
        ;
      inherit (monitor) name;
      domain = config.${namespace}.hardware.networking.domain;
      defaultAddress = if domain != "" then "${serviceName}.${domain}" else serviceName;
      address = if monitor.address != "" then monitor.address else defaultAddress;
      port = if monitor.port != null then monitor.port else srv.port.number;
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
      # Everything must run in nspawn containers and gatus as a service is redefined in modules/nixos/services/gatus to operate that way.
      # The default nixos gatus pkg is forcefully disabled here to prevent it from running on on the host.
      services.gatus = disabled // {
        settings = gatusSettings;
      };
    }
  ];
}
