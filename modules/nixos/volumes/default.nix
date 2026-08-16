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
    mkForce
    mkMerge
    optional
    unique
    ;

  cfg = config.${namespace};
  currentHost = config.networking.hostName;

  inherit (cfg) volumes;
  inherit (cfg) deletedVolumes;
  services = cfg.services or { };
  allServiceNames = attrNames services;
  enabledServices = filterAttrs (_name: srv: srv.enable or false) services;

  volumeHostPath = volume: "/var/lib/volumes/${volume.name}";
  volumeMountUnit = volume: "${utils.escapeSystemdPath (volumeHostPath volume)}.mount";
  serviceVolumeIds = srv: srv.volumes or [ ];
  existingServiceVolumeIds = srv: filter (volumeId: hasAttr volumeId volumes) (serviceVolumeIds srv);
  serviceVolumes = srv: map (volumeId: volumes.${volumeId}) (existingServiceVolumeIds srv);

  volumesOnHost = filterAttrs (_volumeId: volume: volume.host == currentHost) volumes;

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

  wrongHostRefs = flatten (
    mapAttrsToList (
      serviceName: srv:
      map (
        volumeId:
        let
          volume = volumes.${volumeId};
        in
        "${serviceName}:${volumeId} is on ${volume.host}, not ${currentHost}"
      ) (filter (volumeId: volumes.${volumeId}.host != currentHost) (existingServiceVolumeIds srv))
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

  mixedNamespaceServices = filter (
    serviceName:
    let
      namespaceBases = unique (
        map (volume: volume.owner.namespaceBase) (serviceVolumes services.${serviceName})
      );
    in
    length namespaceBases > 1
  ) allServiceNames;

  mixedOwnerServices = filter (
    serviceName:
    let
      ownerPairs = unique (
        map (volume: "${toString volume.owner.uid}:${toString volume.owner.gid}") (
          serviceVolumes services.${serviceName}
        )
      );
    in
    length ownerPairs > 1
  ) allServiceNames;

  namespaceBasesOnHost = unique (map (volume: volume.owner.namespaceBase) (attrValues volumesOnHost));
  invalidNamespaceBases = flatten (
    mapAttrsToList (
      volumeId: volume:
      optional (
        volume.owner.namespaceBase != (builtins.div volume.owner.namespaceBase 65536) * 65536
      ) "${volumeId}:${toString volume.owner.namespaceBase}"
    ) volumes
  );
  duplicateNamespaceBases = filter (
    namespaceBase:
    length (
      unique (
        map (volume: volume.ownerService) (
          filter (volume: volume.owner.namespaceBase == namespaceBase) (attrValues volumesOnHost)
        )
      )
    ) > 1
  ) namespaceBasesOnHost;

  activeDeletedVolumes = filter (volumeId: hasAttr volumeId volumes) (attrNames deletedVolumes);

  ownerHostUid = volume: volume.owner.namespaceBase + volume.owner.uid;
  ownerHostGid = volume: volume.owner.namespaceBase + volume.owner.gid;
  volumeLvPath = volume: "/dev/pool/${volume.name}";
  volumeHostMode = volume: removePrefix "0" volume.owner.mode;
  volumePrepareUnit = volume: "homelab-volume-${volume.name}.service";

  mkVolumeHostTmpfilesRule =
    _volumeId: volume:
    "d ${volumeHostPath volume} ${volume.owner.mode} ${toString (ownerHostUid volume)} ${toString (ownerHostGid volume)} -";

  mkVolumePrepareScript =
    volumeId: volume:
    pkgs.writeShellApplication {
      name = "homelab-volume-prepare-${volume.name}";
      runtimeInputs = with pkgs; [
        coreutils
        e2fsprogs
        lvm2
        util-linux
      ];
      text = ''
        lv=${escapeShellArg (volumeLvPath volume)}
        declared_size=${escapeShellArg volume.size}
        expected_size="$(numfmt --from=iec "$declared_size")"

        if [ ! -b "$lv" ]; then
          echo "${volumeId}: missing block device: $lv" >&2
          exit 1
        fi

        actual_size="$(blockdev --getsize64 "$lv")"

        if [ "$actual_size" -gt "$expected_size" ]; then
          echo "${volumeId}: declared size $declared_size is smaller than actual block size $actual_size bytes" >&2
          echo "${volumeId}: refusing to shrink automatically" >&2
          exit 1
        fi

        if [ "$actual_size" -lt "$expected_size" ]; then
          echo "${volumeId}: growing $lv from $actual_size bytes to $declared_size"
          lvextend --yes --size "$declared_size" "$lv"
          resize2fs "$lv"
        fi
      '';
    };

  mkVolumePrepareService =
    volumeId: volume:
    let
      script = mkVolumePrepareScript volumeId volume;
    in
    {
      "homelab-volume-${volume.name}" = {
        description = "Prepare homelab volume ${volumeId}";
        wantedBy = [ "multi-user.target" ];
        requires = [ (volumeMountUnit volume) ];
        after = [ (volumeMountUnit volume) ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${script}/bin/homelab-volume-prepare-${volume.name}";
        };
      };
    };

  mkVolumeRuntimeCheck =
    volumeId: volume:
    let
      lvPath = volumeLvPath volume;
      hostPath = volumeHostPath volume;
    in
    ''
      echo "checking ${volumeId}"

      lv=${escapeShellArg lvPath}
      path=${escapeShellArg hostPath}
      declared_size=${escapeShellArg volume.size}
      expected_size="$(numfmt --from=iec "$declared_size")"
      expected_uuid=${escapeShellArg volume.uuid}
      expected_owner=${escapeShellArg "${toString (ownerHostUid volume)}:${toString (ownerHostGid volume)}"}
      expected_mode=${escapeShellArg (volumeHostMode volume)}

      if [ ! -b "$lv" ]; then
        echo "  missing block device: $lv"
        status=1
      else
        actual_size="$(blockdev --getsize64 "$lv")"
        if [ "$actual_size" -gt "$expected_size" ]; then
          echo "  declared size is smaller than actual: declared $declared_size, actual $actual_size bytes"
          status=1
        elif [ "$actual_size" -lt "$expected_size" ]; then
          echo "  actual size is smaller than declared: declared $declared_size, actual $actual_size bytes"
          status=1
        fi

        actual_uuid="$(blkid -s UUID -o value "$lv" 2>/dev/null || true)"
        if [ "$actual_uuid" != "$expected_uuid" ]; then
          echo "  uuid mismatch: expected $expected_uuid, got ''${actual_uuid:-missing}"
          status=1
        fi
      fi

      if ! findmnt -rn --target "$path" >/dev/null 2>&1; then
        echo "  not mounted: $path"
        status=1
      else
        expected_source="$(readlink -f "$lv" 2>/dev/null || true)"
        actual_source="$(findmnt -rn -o SOURCE --target "$path" 2>/dev/null || true)"
        actual_source="$(readlink -f "$actual_source" 2>/dev/null || true)"
        if [ "$actual_source" != "$expected_source" ]; then
          echo "  source mismatch: expected $expected_source, got ''${actual_source:-missing}"
          status=1
        fi
      fi

      actual_owner="$(stat -c '%u:%g' "$path" 2>/dev/null || true)"
      if [ "$actual_owner" != "$expected_owner" ]; then
        echo "  owner mismatch: expected $expected_owner, got ''${actual_owner:-missing}"
        status=1
      fi

      actual_mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
      if [ "$actual_mode" != "$expected_mode" ]; then
        echo "  mode mismatch: expected $expected_mode, got ''${actual_mode:-missing}"
        status=1
      fi
    '';

  volumeCheckScript = pkgs.writeShellApplication {
    name = "volume-check";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
    ];
    text = ''
      status=0
      ${optionalString (volumesOnHost == { }) ''
        echo "no homelab volumes declared for ${currentHost}"
      ''}
      ${concatStringsSep "\n" (mapAttrsToList mkVolumeRuntimeCheck volumesOnHost)}
      exit "$status"
    '';
  };

  mkVolumeDisko = _volumeId: volume: {
    lvm_vg.pool.lvs.${volume.name} = {
      inherit (volume) size;
      content = {
        type = "filesystem";
        format = volume.fsType;
        mountpoint = volumeHostPath volume;
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
        host
        ownerService
        mountPath
        ;
      isMigratable = volume.migratable;
      lvPath = volumeLvPath volume;
      hostPath = volumeHostPath volume;
      owner = {
        inherit (volume.owner)
          user
          uid
          group
          gid
          mode
          namespaceBase
          ;
        hostUid = ownerHostUid volume;
        hostGid = ownerHostGid volume;
      };
    };
  };

  mkServiceVolumeConfig =
    serviceName: srv:
    let
      attachedVolumes = serviceVolumes srv;
      firstVolume = builtins.head attachedVolumes;
      hasVolumes = attachedVolumes != [ ];
    in
    if hasVolumes then
      {
        containers.${serviceName} = {
          privateUsers = mkForce firstVolume.owner.namespaceBase;
          extraFlags = [ "--private-users-ownership=map" ];

          bindMounts = mkMerge (
            map (volume: {
              ${volume.mountPath} = {
                hostPath = volumeHostPath volume;
                isReadOnly = volume.readOnly;
              };
            }) attachedVolumes
          );

          config = {
            users.groups.${firstVolume.owner.group} = {
              gid = firstVolume.owner.gid;
            };
            users.users.${firstVolume.owner.user} = {
              isSystemUser = true;
              uid = firstVolume.owner.uid;
              group = firstVolume.owner.group;
            };

            systemd.tmpfiles.rules = map (
              volume: "d ${volume.mountPath} ${volume.owner.mode} ${volume.owner.user} ${volume.owner.group} -"
            ) attachedVolumes;

            systemd.services.${serviceName}.serviceConfig = {
              DynamicUser = mkForce false;
              User = firstVolume.owner.user;
              Group = firstVolume.owner.group;
            };
          };
        };

        systemd.services."container@${serviceName}" = {
          requires = map volumePrepareUnit attachedVolumes;
          after = (map volumeMountUnit attachedVolumes) ++ (map volumePrepareUnit attachedVolumes);
          bindsTo = map volumeMountUnit attachedVolumes;
        };
      }
    else
      { };
in
{
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
            host = mkOption {
              type = types.str;
              description = "Host that owns and mounts this volume.";
            };
            ownerService = mkOption {
              type = types.str;
              description = "Service that owns this volume.";
            };
            mountPath = mkOption {
              type = types.str;
              description = "Path where the volume is mounted inside the service container.";
            };
            size = mkOption {
              type = types.str;
              description = "Logical volume size.";
            };
            fsType = mkOpt (types.enum [ "ext4" ]) "ext4" "Filesystem type.";
            backend = mkOpt (types.enum [ "lvm" ]) "lvm" "Volume backend.";
            migratable = mkBoolOpt false "Whether this volume is managed by migration tooling.";
            readOnly = mkBoolOpt false "Whether to bind mount this volume read-only.";
            owner = {
              user = mkOption {
                type = types.str;
                description = "User that owns the mounted data inside the container.";
              };
              uid = mkOption {
                type = types.int;
                description = "Stable numeric UID that owns the mounted data inside the container.";
              };
              group = mkOption {
                type = types.str;
                description = "Group that owns the mounted data inside the container.";
              };
              gid = mkOption {
                type = types.int;
                description = "Stable numeric GID that owns the mounted data inside the container.";
              };
              namespaceBase = mkOption {
                type = types.int;
                description = "Stable host UID/GID namespace base for this unprivileged container.";
              };
              mode = mkOpt types.str "0700" "Directory mode for the mounted data inside the container.";
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
          assertion = wrongHostRefs == [ ];
          message = "Services reference volumes that are not placed on this host: ${concatStringsSep ", " wrongHostRefs}";
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
          assertion = mixedOwnerServices == [ ];
          message = "Services have attached volumes with mixed owner UIDs/GIDs: ${concatStringsSep ", " mixedOwnerServices}";
        }
        {
          assertion = mixedNamespaceServices == [ ];
          message = "Services have attached volumes with mixed namespace bases: ${concatStringsSep ", " mixedNamespaceServices}";
        }
        {
          assertion = invalidNamespaceBases == [ ];
          message = "Volume namespace bases must be multiples of 65536 for systemd-nspawn ownership adjustment: ${concatStringsSep ", " invalidNamespaceBases}";
        }
        {
          assertion = duplicateNamespaceBases == [ ];
          message = "Multiple services use the same volume namespace base on ${currentHost}: ${concatStringsSep ", " (map toString duplicateNamespaceBases)}";
        }
        {
          assertion = activeDeletedVolumes == [ ];
          message = "Volumes are both active and tombstoned: ${concatStringsSep ", " activeDeletedVolumes}";
        }
      ];
    }

    {
      disko.devices = mkMerge (mapAttrsToList mkVolumeDisko volumesOnHost);
    }

    {
      environment.systemPackages = [ volumeCheckScript ];
      systemd.tmpfiles.rules = mapAttrsToList mkVolumeHostTmpfilesRule volumesOnHost;
    }

    {
      systemd.services = mkMerge (mapAttrsToList mkVolumePrepareService volumesOnHost);
    }

    {
      system.migration.volumes = mkMerge (
        mapAttrsToList (
          volumeId: volume: mkIf volume.migratable (mkVolumeMigration volumeId volume)
        ) volumesOnHost
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
