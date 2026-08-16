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
    mkMerge
    mapAttrsToList
    filterAttrs
    ;

  allServices = config.${namespace}.services or { };
  enabledServices = filterAttrs (_name: srv: srv.enable or false) allServices;
  gatus = allServices.gatus or { };

  serviceEndpoints = mapAttrsToList (
    serviceName: srv:
    let
      monitor = srv.monitor or { };
      name = monitor.name or serviceName;
      inherit (monitor) group;
      inherit (monitor) protocol;
      domain = config.${namespace}.hardware.networking.domain;
      defaultAddress = if domain != "" then "${serviceName}.${domain}" else serviceName;
      address = if monitor.address != "" then monitor.address else defaultAddress;
      port = if monitor.port != null then monitor.port else srv.port;
      path = monitor.path or "/";
      url =
        if protocol == "http" || protocol == "https" then
          "${protocol}://${address}:${toString port}${path}"
        else
          "${protocol}://${address}:${toString port}";
    in
    {
      inherit name group url;
      interval = monitor.interval or gatus.defaultInterval;
      inherit (monitor) conditions;
    }
  ) (filterAttrs (_name: srv: srv.monitor.enable or false) enabledServices);

  gatusSettings.endpoints = serviceEndpoints ++ gatus.externalEndpoints;
in
{
  config = mkMerge [
    {
      # Everything must run in nspawn containers and gatus as a service is redefined in modules/nixos/services/gatus to operate that way.
      # The default nixos gatus pkg is forcefully disabled here to prevent it from running on on the host.
      services.gatus = disabled // {
        settings = gatusSettings;
      };
    }
  ];
}
