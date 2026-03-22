{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
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

  # Helper to escape path for systemd unit names
  toMountUnit = path: "${utils.escapeSystemdPath path}.mount";
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
  ];
}
