{ lib, ... }:
{
  mkFleetRegistry =
    hostRegistries:
    let
      mkFleetEntries =
        select:
        builtins.concatLists (
          lib.mapAttrsToList (
            hostName: registry:
            lib.mapAttrsToList (name: declaration: {
              inherit name;
              value = declaration // {
                host = hostName;
              };
            }) (select registry)
          ) hostRegistries
        );

      mkUniqueFleetAttrs =
        kind: entries:
        let
          names = map (entry: entry.name) entries;
          duplicateNames = lib.unique (
            builtins.filter (
              name: builtins.length (builtins.filter (candidate: candidate == name) names) > 1
            ) names
          );
        in
        if duplicateNames != [ ] then
          throw "Duplicate active homelab ${kind} names across hosts: ${builtins.concatStringsSep ", " duplicateNames}"
        else
          builtins.listToAttrs entries;

      serviceEntries = mkFleetEntries (
        registry: lib.filterAttrs (_name: service: service.enable) registry.services
      );
      volumeEntries = mkFleetEntries (registry: registry.volumes);
    in
    {
      schemaVersion = 1;
      hosts = builtins.mapAttrs (_hostName: registry: registry.host) hostRegistries;
      services = mkUniqueFleetAttrs "service" serviceEntries;
      volumes = mkUniqueFleetAttrs "volume" volumeEntries;
    };
}
