{ lib, ... }:
{
  mkFleetRegistry =
    {
      hostRegistries,
      hostVolumes,
      hostWorkloads,
    }:
    let
      mkFleetEntries =
        hostDeclarations: select:
        builtins.concatLists (
          lib.mapAttrsToList (
            hostName: declarations:
            lib.mapAttrsToList (name: _declaration: {
              inherit name;
              value = (select hostRegistries.${hostName}).${name} // {
                host = hostName;
              };
            }) declarations
          ) hostDeclarations
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

      enabledHostWorkloads = builtins.mapAttrs (
        hostName: workloads:
        lib.filterAttrs (
          name: _workload:
          builtins.hasAttr name hostRegistries.${hostName}.services
          && hostRegistries.${hostName}.services.${name}.enable
        ) workloads
      ) hostWorkloads;

      serviceEntries = mkFleetEntries enabledHostWorkloads (registry: registry.services);
      volumeEntries = mkFleetEntries hostVolumes (registry: registry.volumes);
    in
    {
      schemaVersion = 1;
      hosts = builtins.mapAttrs (_hostName: registry: registry.host) hostRegistries;
      services = mkUniqueFleetAttrs "service" serviceEntries;
      volumes = mkUniqueFleetAttrs "volume" volumeEntries;
    };
}
