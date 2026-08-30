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
    attrNames
    attrValues
    filter
    filterAttrs
    flatten
    hasAttr
    length
    mapAttrsToList
    mkMerge
    optional
    unique
    ;

  cfg = config.${namespace};
  inherit (cfg) volumes;
  inherit (cfg) deletedVolumes;
  inherit (cfg) services;
  volumeServices = filterAttrs (_name: srv: srv ? volumes) services;
  enabledServices = filterAttrs (_name: srv: srv.enable or false) volumeServices;

  volumeHostPath = volume: "/var/lib/volumes/${volume.name}";
  volumeMountUnit = volume: "${utils.escapeSystemdPath (volumeHostPath volume)}.mount";
  serviceVolumeIds = srv: srv.volumes;
  existingServiceVolumeIds = srv: filter (volumeId: hasAttr volumeId volumes) (serviceVolumeIds srv);
  serviceVolumes = srv: map (volumeId: volumes.${volumeId}) (existingServiceVolumeIds srv);

  volumeUuidList = map (volume: volume.uuid) (attrValues volumes);
  duplicateUuids = unique (
    filter (uuid: length (filter (candidate: candidate == uuid) volumeUuidList) > 1) volumeUuidList
  );

  missingVolumeRefs = flatten (
    mapAttrsToList (
      serviceName: srv:
      map (volumeId: "${serviceName}:${volumeId}") (
        filter (volumeId: !(hasAttr volumeId volumes)) (serviceVolumeIds srv)
      )
    ) volumeServices
  );

  wrongOwnerRefs = flatten (
    mapAttrsToList (
      serviceName: srv:
      map
        (
          volumeId:
          let
            volume = volumes.${volumeId};
          in
          "${serviceName}:${volumeId} is owned by ${volume.ownerService}"
        )
        (filter (volumeId: volumes.${volumeId}.ownerService != serviceName) (existingServiceVolumeIds srv))
    ) volumeServices
  );

  missingOwnerServices = flatten (
    mapAttrsToList (
      volumeId: volume:
      optional (!(hasAttr volume.ownerService services)) "${volumeId}:${volume.ownerService}"
    ) volumes
  );

  activeDeletedVolumes = filter (volumeId: hasAttr volumeId volumes) (attrNames deletedVolumes);

  volumeOwnerService = volume: services.${volume.ownerService};
  volumeOwner =
    volume:
    let
      service = volumeOwnerService volume;
      inherit (service) runtimeId runtimeUser;
    in
    runtimeUser
    // {
      uid = if runtimeUser.uid != null then runtimeUser.uid else runtimeId;
      gid = if runtimeUser.gid != null then runtimeUser.gid else runtimeId;
    };
  ownerHostUid = volume: containerUidOffset + (volumeOwner volume).uid;
  ownerHostGid = volume: containerUidOffset + (volumeOwner volume).gid;
  volumeLvPath = volume: "/dev/pool/${volume.name}";

  mkVolumeHostTmpfilesRule =
    _volumeId: volume:
    "d ${volumeHostPath volume} ${volume.mode} ${toString (ownerHostUid volume)} ${toString (ownerHostGid volume)} -";

  mkVolumeDisko = _volumeId: volume: {
    lvm_vg.pool.lvs.${volume.name} = {
      inherit (volume) size;
      content = {
        type = "filesystem";
        format = volume.fsType;
        mountpoint = volumeHostPath volume;
        mountOptions = [
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
        extraArgs = [
          "-U"
          volume.uuid
        ];
      };
    };
  };

  mkVolumeMigration = volumeId: volume: {
    ${volumeId} = {
      inherit volumeId;
      inherit (volume)
        uuid
        ownerService
        mountPath
        size
        fsType
        ;
      isMigratable = volume.migratable;
      lvPath = volumeLvPath volume;
      hostPath = volumeHostPath volume;
      owner = {
        inherit (volume) mode;
        user = (volumeOwner volume).name;
        inherit (volumeOwner volume) uid group gid;
        namespaceBase = containerUidOffset;
        hostUid = ownerHostUid volume;
        hostGid = ownerHostGid volume;
      };
    };
  };

  mkServiceVolumeConfig =
    serviceName: srv:
    let
      attachedVolumes = serviceVolumes srv;
      hasVolumes = attachedVolumes != [ ];
    in
    if hasVolumes then
      {
        containers.${serviceName} = {
          bindMounts = mkMerge (
            map (volume: {
              ${volume.mountPath} = {
                hostPath = volumeHostPath volume;
                isReadOnly = volume.readOnly;
              };
            }) attachedVolumes
          );

          config = {
            systemd.tmpfiles.rules = map (
              volume:
              let
                owner = volumeOwner volume;
              in
              "d ${volume.mountPath} ${volume.mode} ${owner.name} ${owner.group} -"
            ) attachedVolumes;
          };
        };

        systemd.services."container@${serviceName}" = {
          requires = map volumeMountUnit attachedVolumes;
          after = map volumeMountUnit attachedVolumes;
          bindsTo = map volumeMountUnit attachedVolumes;
        };
      }
    else
      { };
in
{
  options.system.homelab.volumes = mkOption {
    type = types.attrsOf types.anything;
    default = { };
    internal = true;
    description = "Evaluated homelab volume metadata for shell tooling.";
  };

  options.${namespace} = {
    volumes = mkOpt (types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            name = mkOpt types.str name "LVM logical volume name.";
            uuid = mkOption {
              type = types.str;
              description = "Filesystem UUID. This is the stable identity of the volume.";
            };
            ownerService = mkOpt types.str name "Service that owns this volume.";
            mountPath =
              mkOpt types.str "/var/lib/${name}"
                "Path where the volume is mounted inside the service container.";
            size = mkOption {
              type = types.str;
              description = "Logical volume size.";
            };
            fsType = mkOpt (types.enum [ "ext4" ]) "ext4" "Filesystem type.";
            backend = mkOpt (types.enum [ "lvm" ]) "lvm" "Volume backend.";
            migratable = mkBoolOpt true "Whether this volume is managed by migration tooling.";
            readOnly = mkBoolOpt false "Whether to bind mount this volume read-only.";
            mode = mkOpt types.str "0700" "Directory mode for the mounted data inside the container.";
          };
        }
      )
    )) { } "Global service volume registry.";

    deletedVolumes = mkOpt (types.attrsOf (
      types.submodule {
        options = {
          uuid = mkOption {
            type = types.str;
            description = "UUID of the deleted volume.";
          };
          after = mkOption {
            type = types.str;
            description = "Date after which manual GC may remove the volume.";
          };
          reason = mkOpt types.str "" "Reason for deleting the volume.";
        };
      }
    )) { } "Explicit tombstones for volumes that may be garbage collected manually.";
  };

  config = mkMerge [
    {
      assertions = [
        {
          assertion = duplicateUuids == [ ];
          message = "Duplicate homelab volume UUIDs: ${concatStringsSep ", " duplicateUuids}";
        }
        {
          assertion = missingVolumeRefs == [ ];
          message = "Services reference missing homelab volumes: ${concatStringsSep ", " missingVolumeRefs}";
        }
        {
          assertion = wrongOwnerRefs == [ ];
          message = "Services reference volumes owned by another service: ${concatStringsSep ", " wrongOwnerRefs}";
        }
        {
          assertion = missingOwnerServices == [ ];
          message = "Volumes reference missing owner services: ${concatStringsSep ", " missingOwnerServices}";
        }
        {
          assertion = all (
            volume: hasAttr volume.ownerService services && services.${volume.ownerService} ? runtimeUser
          ) (attrValues volumes);
          message = "Every volume ownerService must point at a service with runtimeUser.";
        }
        {
          assertion = activeDeletedVolumes == [ ];
          message = "Volumes are both active and tombstoned: ${concatStringsSep ", " activeDeletedVolumes}";
        }
      ];
    }

    {
      disko.devices = mkMerge (mapAttrsToList mkVolumeDisko volumes);
    }

    {
      systemd.tmpfiles.rules = mapAttrsToList mkVolumeHostTmpfilesRule volumes;
    }

    {
      system.homelab.volumes = mkMerge (mapAttrsToList mkVolumeMigration volumes);
    }

    {
      system.migration.volumes = mkMerge (
        mapAttrsToList (
          volumeId: volume: mkIf volume.migratable (mkVolumeMigration volumeId volume)
        ) volumes
      );
    }

    {
      containers = mkMerge (
        mapAttrsToList (
          serviceName: srv: (mkServiceVolumeConfig serviceName srv).containers or { }
        ) enabledServices
      );
    }

    {
      systemd.services = mkMerge (
        mapAttrsToList (
          serviceName: srv: (mkServiceVolumeConfig serviceName srv).systemd.services or { }
        ) enabledServices
      );
    }
  ];
}
