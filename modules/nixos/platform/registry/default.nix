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
  hostName = config.networking.hostName;
  shares = config.${namespace}.shares;
  volumes = config.${namespace}.volumes;
  volumeOwnerServices = unique (map (volume: volume.ownerService) (attrValues volumes));
  services = filterAttrs (
    name: service: service ? runtimeUser && (service.enable || elem name volumeOwnerServices)
  ) config.${namespace}.services;

  mkService = _name: service: {
    inherit (service)
      description
      devices
      endpoints
      enable
      logging
      monitor
      name
      runtimeId
      shares
      vlans
      volumes
      ;
    inherit (service) runtimeUser;
  };

  registry = {
    host = {
      name = hostName;
      system = pkgs.stdenv.hostPlatform.system;
    };
    services = mapAttrs mkService services;
    inherit shares volumes;
  };

  servicesWithoutRuntimeIds = attrNames (filterAttrs (_name: service: service.runtimeId == null) registry.services);
in
{
  options.system.homelab.registry = mkOption {
    type = types.attrsOf types.anything;
    default = { };
    internal = true;
    description = "Normalized registry of homelab services and volumes on this host.";
  };

  config = {
    assertions = [
      {
        assertion = servicesWithoutRuntimeIds == [ ];
        message = "Homelab services placed on this host require runtimeId: ${concatStringsSep ", " servicesWithoutRuntimeIds}";
      }
    ];

    system.homelab.registry = registry;
  };
}
