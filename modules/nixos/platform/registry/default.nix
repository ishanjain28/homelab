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
  json = pkgs.formats.json { };
  hostName = config.networking.hostName;
  volumes = config.${namespace}.volumes;
  volumeOwnerServices = unique (map (volume: volume.ownerService) (attrValues volumes));
  services = filterAttrs (
    name: service: service ? runtimeUser && (service.enable || elem name volumeOwnerServices)
  ) config.${namespace}.services;

  mkService = _name: service: {
    inherit (service)
      description
      endpoints
      enable
      logging
      monitor
      name
      runtimeId
      vlan
      volumes
      ;
    inherit (service) runtimeUser;
  };

  registry = {
    schemaVersion = 1;
    host = {
      name = hostName;
      system = pkgs.stdenv.hostPlatform.system;
    };
    services = mapAttrs mkService services;
    inherit volumes;
  };

  registryFile = json.generate "homelab-registry-${hostName}.json" registry;
  servicesWithoutRuntimeIds = attrNames (
    filterAttrs (_name: service: service.runtimeId == null) registry.services
  );
in
{
  options.system.homelab.registry = mkOption {
    type = types.attrsOf types.anything;
    default = { };
    internal = true;
    description = "Normalized JSON-safe registry of homelab services and volumes on this host.";
  };

  config = {
    assertions = [
      {
        assertion = servicesWithoutRuntimeIds == [ ];
        message = "Homelab services placed on this host require runtimeId: ${concatStringsSep ", " servicesWithoutRuntimeIds}";
      }
    ];

    system.homelab.registry = registry;
    environment.etc."homelab/registry.json".source = registryFile;
  };
}
