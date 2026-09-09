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
  volumePackage = pkgs.callPackage ../../../packages/volume { };
  volumeStateFile = json.generate "homelab-volumes.json" config.system.homelab.volumes;
  cfg = config.${namespace};
  registry = config.system.homelab.registry;
  inherit (registry) services volumes;
  inherit (cfg) deletedVolumes;
  enabledServices = filterAttrs (_name: service: service.enable) services;

  volumeHostPath = volume: "/var/lib/volumes/${volume.name}";
  volumeApplyUnit = volumeId: "homelab-volume-${volumeId}.service";
  volumeMountUnit = volume: "var-lib-volumes-${replaceStrings [ "-" ] [ "\\x2d" ] volume.name}.mount";
  volumePermissionsUnit = volumeId: "homelab-volume-${volumeId}-permissions.service";
  volumeMountOptions = [
    "nofail"
    "x-systemd.device-timeout=10s"
  ];
  volumeState = volumeId: {
    ${volumeId} = config.system.homelab.volumes.${volumeId};
  };
  volumeStatePath = volumeId: json.generate "homelab-volume-${volumeId}.json" (volumeState volumeId);
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
    ) services
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
    ) services
  );

  missingOwnerServices = flatten (
    mapAttrsToList (
      volumeId: volume:
      optional (!(hasAttr volume.ownerService services)) "${volumeId}:${volume.ownerService}"
    ) volumes
  );

  activeDeletedVolumes = filter (volumeId: hasAttr volumeId volumes) (attrNames deletedVolumes);

  volumeOwnerService = volume: services.${volume.ownerService};
  volumeOwner = volume: (volumeOwnerService volume).runtimeUser;
  ownerHostUid = volume: containerUidOffset + (volumeOwnerService volume).runtimeId;
  ownerHostGid = volume: containerUidOffset + (volumeOwnerService volume).runtimeId;
  volumeLvPath = volume: "/dev/pool/${volume.name}";

  mkVolumeState = volumeId: volume: {
    inherit volumeId;
    inherit (volume) uuid size fsType;
    lvPath = volumeLvPath volume;
  };

  mkVolumeApplyService = volumeId: _volume: {
    "homelab-volume-${volumeId}" = {
      description = "Apply homelab volume '${volumeId}'";
      path = with pkgs; [
        coreutils
        e2fsprogs
        lvm2
        util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${volumePackage}/bin/volume --state-file ${volumeStatePath volumeId} apply --yes ${escapeShellArg volumeId}";
        RemainAfterExit = true;
      };
    };
  };

  mkVolumePermissionsService = volumeId: volume: {
    "homelab-volume-${volumeId}-permissions" = {
      description = "Apply permissions for homelab volume '${volumeId}'";
      wantedBy = [ "multi-user.target" ];
      partOf = [ (volumeMountUnit volume) ];
      requires = [ (volumeMountUnit volume) ];
      after = [ (volumeMountUnit volume) ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "${pkgs.coreutils}/bin/chown ${toString (ownerHostUid volume)}:${toString (ownerHostGid volume)} ${escapeShellArg (volumeHostPath volume)}"
          "${pkgs.coreutils}/bin/chmod ${volume.mode} ${escapeShellArg (volumeHostPath volume)}"
        ];
        RemainAfterExit = true;
      };
    };
  };

  mkVolumeMountOrdering = volumeId: volume: {
    what = volumeLvPath volume;
    where = volumeHostPath volume;
    type = volume.fsType;
    options = concatStringsSep "," volumeMountOptions;
    wantedBy = [ "local-fs.target" ];
    unitConfig = {
      After = [ (volumeApplyUnit volumeId) ];
      PartOf = [ (volumeApplyUnit volumeId) ];
      Requires = [ (volumeApplyUnit volumeId) ];
    };
    mountConfig.DirectoryMode = volume.mode;
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
          restartTriggers = map volumeStatePath (existingServiceVolumeIds srv);
          partOf = map volumeMountUnit attachedVolumes;
          requires =
            map volumeApplyUnit (existingServiceVolumeIds srv)
            ++ map volumeMountUnit attachedVolumes
            ++ map volumePermissionsUnit (existingServiceVolumeIds srv);
          after =
            map volumeApplyUnit (existingServiceVolumeIds srv)
            ++ map volumeMountUnit attachedVolumes
            ++ map volumePermissionsUnit (existingServiceVolumeIds srv);
        };
      }
    else
      {
        containers = { };
        systemd.services = { };
      };
  serviceVolumeConfigs = mapAttrsToList mkServiceVolumeConfig enabledServices;
in
{
  options.system.homelab.volumes = mkOption {
    type = types.attrsOf types.anything;
    default = { };
    internal = true;
    description = "Evaluated homelab volume metadata.";
  };

  options.${namespace} = {
    volumes = mkOpt (types.attrsOf (
      types.submodule (
        { name, ... }: {
          options = {
            name = mkOpt (types.strMatching "[a-z0-9][a-z0-9-]*") name "LVM logical volume name.";
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
            readOnly = mkBoolOpt false "Whether to bind mount this volume read-only.";
            mode = mkOpt types.str "0700" "Directory mode for the mounted data inside the container.";
            backup = mkOption {
              type = types.nullOr (
                types.submodule {
                  options = {
                    target = mkOption {
                      type = types.str;
                      description = "Named homelab backup target.";
                    };
                    onCalendar = mkOpt types.str "daily" "systemd calendar expression for this backup.";
                    randomizedDelaySec = mkOpt types.str "1h" "Maximum randomized delay applied to the backup timer.";
                    snapshotSize = mkOption {
                      type = types.str;
                      description = "LVM COW space allocated to the temporary backup snapshot.";
                    };
                  };
                }
              );
              default = null;
              description = "Backup policy. Declaring this attribute opts the volume into backups.";
            };
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

    { system.homelab.volumes = mapAttrs mkVolumeState volumes; }

    {
      environment.systemPackages = [ volumePackage ];
      environment.etc."homelab/volumes.json".source = volumeStateFile;
    }

    {
      systemd.services = mkMerge (
        mapAttrsToList mkVolumeApplyService volumes
        ++ mapAttrsToList mkVolumePermissionsService volumes
        ++ map (fragment: fragment.systemd.services) serviceVolumeConfigs
      );
    }

    { systemd.mounts = mapAttrsToList mkVolumeMountOrdering volumes; }

    {
      containers = mkMerge (map (fragment: fragment.containers) serviceVolumeConfigs);
    }
  ];
}
