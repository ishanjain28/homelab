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
  utils = import "${pkgs.path}/nixos/lib/utils.nix" { inherit lib config pkgs; };
  inherit (lib)
    mkIf
    mkMerge
    mapAttrsToList
    filterAttrs
    ;

  allServices = config.${namespace}.services or { };
  enabledServices = filterAttrs (_name: srv: srv.enable or false) allServices;
  gatus = allServices.gatus or { };

  # Helper to escape path for systemd unit names
  toMountUnit = path: "${utils.escapeSystemdPath path}.mount";

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
    # 1. Merge all disko configurations from all services
    {
      disko.devices = mkMerge (
        mapAttrsToList (
          _srvName: srv:
          mkMerge (mapAttrsToList (_volName: v: v.disko.devices or { }) (srv.volumeConfig or { }))
        ) enabledServices
      );
    }

    # 2. Merge all container configurations (bind mounts) from all services
    {
      containers = mkMerge (
        mapAttrsToList (
          _srvName: srv: mkMerge (mapAttrsToList (_volName: v: v.containers or { }) (srv.volumeConfig or { }))
        ) enabledServices
      );
    }

    # 3. Merge all migration configurations
    {
      system.migration.volumes = mkMerge (
        mapAttrsToList (
          _srvName: srv:
          mkMerge (mapAttrsToList (_volName: v: v.system.migration.volumes or { }) (srv.volumeConfig or { }))
        ) enabledServices
      );
    }

    # 4. Automatically add systemd dependencies for containers
    {
      systemd.services = mkMerge (
        mapAttrsToList (srvName: srv: {
          "container@${srvName}" = mkIf (srv.volumeConfig or { } != { }) {
            after =
              let
                # Extract all LV names from this service's volumeConfig
                lvNames = lib.flatten (
                  mapAttrsToList (
                    _volKey: v: mapAttrsToList (lvName: _lv: lvName) (v.disko.devices.lvm_vg.pool.lvs or { })
                  ) srv.volumeConfig
                );
              in
              map (name: toMountUnit "/var/lib/volumes/${name}") lvNames;

            bindsTo =
              let
                lvNames = lib.flatten (
                  mapAttrsToList (
                    _volKey: v: mapAttrsToList (lvName: _lv: lvName) (v.disko.devices.lvm_vg.pool.lvs or { })
                  ) srv.volumeConfig
                );
              in
              map (name: toMountUnit "/var/lib/volumes/${name}") lvNames;
          };
        }) enabledServices
      );
    }

    {
      # Everything must run in nspawn containers and gatus as a service is redefined in modules/nixos/services/gatus to operate that way.
      # The default nixos gatus pkg is forcefully disabled here to prevent it from running on on the host.
      services.gatus = disabled // {
        settings = gatusSettings;
      };
    }
  ];
}
