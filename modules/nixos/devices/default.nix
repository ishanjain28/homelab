{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  devices = config.${namespace}.devices;
  services = filterAttrs (_name: service: service.enable) config.${namespace}.services;

  deviceType = types.submodule (
    { name, ... }: {
      options = {
        hostPath = mkOption {
          type = types.strMatching "/.*";
          description = "Device node mounted unchanged into attached service containers.";
        };

        group = mkOpt types.nonEmptyStr name "Group allowed to access the device inside attached service containers.";

        udevMatch = mkOption {
          type = types.nonEmptyStr;
          description = "udev match expressions used to assign the mapped device group.";
        };
      };
    }
  );

  serviceDeviceIds = service: service.devices or [ ];
  availableDeviceIds = service: filter (deviceId: hasAttr deviceId devices) (serviceDeviceIds service);
  serviceDevices = service: map (deviceId: devices.${deviceId}) (availableDeviceIds service);
  missingDeviceRefs = flatten (
    mapAttrsToList (
      serviceName: service:
      map (deviceId: "${serviceName}:${deviceId}") (filter (deviceId: !(hasAttr deviceId devices)) (serviceDeviceIds service))
    ) services
  );
  hostGroupName = deviceId: "homelab-device-${deviceId}";
  deviceGid =
    device:
    config.ids.gids.${device.group} or (throw "Device group '${device.group}' does not have a GID reserved by NixOS.");

  mkServiceConfig =
    serviceName: service:
    let
      deviceIds = availableDeviceIds service;
      attachedDevices = serviceDevices service;
    in
    if deviceIds == [ ] then
      { }
    else
      {
        ${serviceName} = {
          bindMounts = mkMerge (
            map (device: {
              ${device.hostPath} = {
                inherit (device) hostPath;
                isReadOnly = false;
              };
            }) attachedDevices
          );

          allowedDevices = map (device: {
            node = device.hostPath;
            modifier = "rw";
          }) attachedDevices;

          config = {
            users.groups = mkMerge (map (device: { ${device.group}.gid = mkForce (deviceGid device); }) attachedDevices);
            users.users.${service.runtimeUser.name}.extraGroups = map (device: device.group) attachedDevices;
          };
        };
      };
in
{
  options.${namespace}.devices = mkOpt (types.attrsOf deviceType) { } "Host devices available to service containers.";

  config = {
    assertions = [
      {
        assertion = missingDeviceRefs == [ ];
        message = "Enabled services reference unavailable devices on this host: ${concatStringsSep ", " missingDeviceRefs}";
      }
    ];

    users.groups = mapAttrs' (
      deviceId: device: nameValuePair (hostGroupName deviceId) { gid = containerUidOffset + deviceGid device; }
    ) devices;

    services.udev.extraRules = concatStringsSep "\n" (
      mapAttrsToList (deviceId: device: ''${device.udevMatch}, GROUP="${hostGroupName deviceId}", MODE="0660"'') devices
    );

    containers = mkMerge (mapAttrsToList mkServiceConfig services);
  };
}
