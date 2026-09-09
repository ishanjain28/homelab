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
      volumeEntries = builtins.concatLists (
        lib.mapAttrsToList (
          hostName: registry:
          lib.mapAttrsToList (
            volumeId: volume:
            let
              owner = registry.services.${volume.ownerService};
            in
            volume
            // {
              host = hostName;
              inherit volumeId;
              ownerRuntimeId = owner.runtimeId;
              ownerRuntimeUser = owner.runtimeUser;
            }
          ) registry.volumes
        ) hostRegistries
      );
      volumeIds = lib.unique (map (volume: volume.volumeId) volumeEntries);
      immutableVolumeFields = [
        "fsType"
        "mode"
        "mountPath"
        "name"
        "ownerRuntimeId"
        "ownerRuntimeUser"
        "ownerService"
        "readOnly"
        "size"
        "uuid"
      ];
      conflictingVolumeIds = builtins.filter (
        volumeId:
        let
          declarations = builtins.filter (volume: volume.volumeId == volumeId) volumeEntries;
          expected = builtins.intersectAttrs (builtins.listToAttrs (
            map (field: lib.nameValuePair field null) immutableVolumeFields
          )) (builtins.head declarations);
        in
        builtins.any (declaration: builtins.intersectAttrs expected declaration != expected) (
          builtins.tail declarations
        )
      ) volumeIds;
    in
    {
      schemaVersion = 2;
      hosts = builtins.mapAttrs (_hostName: registry: registry.host) hostRegistries;
      services = mkUniqueFleetAttrs "service" serviceEntries;
      volumes =
        if conflictingVolumeIds != [ ] then
          throw "Conflicting homelab volume declarations across hosts: ${builtins.concatStringsSep ", " conflictingVolumeIds}"
        else
          volumeEntries;
    };
}
