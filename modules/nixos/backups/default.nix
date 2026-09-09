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
  cfg = config.${namespace}.backups;
  volumes = config.${namespace}.volumes;
  registry = config.system.homelab.registry;
  inherit (cfg) targets;
  volumePackage = pkgs.callPackage ../../../packages/volume { };
  backedUpVolumes = filterAttrs (_volumeId: volume: volume.backup != null) volumes;
  missingTargets = unique (
    mapAttrsToList (_volumeId: volume: volume.backup.target) (
      filterAttrs (_volumeId: volume: !(hasAttr volume.backup.target targets)) backedUpVolumes
    )
  );

  snapshotName = volume: "${volume.name}-backup";
  snapshotPath = volume: "/dev/pool/${snapshotName volume}";
  snapshotMountPath = volumeId: "/run/homelab-backups/${volumeId}/snapshot";
  serviceUnit = volume: "container@${volume.ownerService}.service";
  markerPath = volumeId: "/run/homelab-backups/${volumeId}/service-was-active";
  lockPath = volume: "/run/lock/homelab-volume-${volume.name}";

  mkPrepareScript =
    volumeId: volume:
    let
      mountPath = snapshotMountPath volumeId;
      marker = markerPath volumeId;
      snapshot = snapshotPath volume;
      unit = serviceUnit volume;
      lock = lockPath volume;
      stateFile = "/etc/homelab/volumes.json";
    in
    ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      snapshot_created=false
      service_stopped=false
      lock_acquired=false

      cleanup_on_error() {
        status=$?
        if "$lock_acquired"; then
          if ${pkgs.util-linux}/bin/mountpoint --quiet ${escapeShellArg mountPath}; then
            ${pkgs.util-linux}/bin/umount ${escapeShellArg mountPath} || true
          fi
          if "$snapshot_created"; then
            ${volumePackage}/bin/volume --state-file ${stateFile} snapshot remove \
              --name ${escapeShellArg (snapshotName volume)} ${escapeShellArg volumeId} || true
          fi
          if "$service_stopped"; then
            ${pkgs.systemd}/bin/systemctl start ${escapeShellArg unit} || true
          fi
          ${pkgs.coreutils}/bin/rm -f ${escapeShellArg "${lock}/owner"}
          ${pkgs.coreutils}/bin/rmdir ${escapeShellArg lock} || true
        fi
        exit "$status"
      }
      trap cleanup_on_error ERR INT TERM

      if ! ${pkgs.coreutils}/bin/mkdir ${escapeShellArg lock}; then
        echo "volume '${volumeId}' is already being backed up or migrated" >&2
        exit 1
      fi
      lock_acquired=true
      ${pkgs.coreutils}/bin/printf '%s\n' "''${INVOCATION_ID:-unknown}" > ${escapeShellArg "${lock}/owner"}

      ${pkgs.coreutils}/bin/install -d -m 0700 ${escapeShellArg mountPath}
      ${pkgs.coreutils}/bin/rm -f ${escapeShellArg marker}

      if ${pkgs.systemd}/bin/systemctl is-active --quiet ${escapeShellArg unit}; then
        ${pkgs.coreutils}/bin/touch ${escapeShellArg marker}
        ${pkgs.systemd}/bin/systemctl stop ${escapeShellArg unit}
        service_stopped=true
      fi

      ${pkgs.coreutils}/bin/sync
      ${volumePackage}/bin/volume --state-file ${stateFile} snapshot create \
        --size ${escapeShellArg volume.backup.snapshotSize} \
        --name ${escapeShellArg (snapshotName volume)} ${escapeShellArg volumeId}
      snapshot_created=true

      ${pkgs.util-linux}/bin/mount \
        --types ${escapeShellArg volume.fsType} \
        --options ro,noload \
        ${escapeShellArg snapshot} ${escapeShellArg mountPath}

      if "$service_stopped"; then
        ${pkgs.systemd}/bin/systemctl start ${escapeShellArg unit}
      fi

      trap - ERR INT TERM
    '';

  mkCleanupScript =
    volumeId: volume:
    let
      mountPath = snapshotMountPath volumeId;
      marker = markerPath volumeId;
      unit = serviceUnit volume;
      lock = lockPath volume;
      stateFile = "/etc/homelab/volumes.json";
    in
    ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      if ! ${pkgs.coreutils}/bin/test -f ${escapeShellArg "${lock}/owner"}; then
        exit 0
      fi
      lock_owner="$(${pkgs.coreutils}/bin/cat ${escapeShellArg "${lock}/owner"})"
      if [ "$lock_owner" != "''${INVOCATION_ID:-unknown}" ]; then
        exit 0
      fi

      status=0
      if ${pkgs.util-linux}/bin/mountpoint --quiet ${escapeShellArg mountPath}; then
        ${pkgs.util-linux}/bin/umount ${escapeShellArg mountPath} || status=$?
      fi
      if ${pkgs.coreutils}/bin/test -b ${escapeShellArg (snapshotPath volume)}; then
        ${volumePackage}/bin/volume --state-file ${stateFile} snapshot remove \
          --name ${escapeShellArg (snapshotName volume)} ${escapeShellArg volumeId} || status=$?
      fi
      if ${pkgs.coreutils}/bin/test -e ${escapeShellArg marker}; then
        if ! ${pkgs.systemd}/bin/systemctl is-active --quiet ${escapeShellArg unit}; then
          ${pkgs.systemd}/bin/systemctl start ${escapeShellArg unit} || status=$?
        fi
        ${pkgs.coreutils}/bin/rm -f ${escapeShellArg marker}
      fi
      ${pkgs.coreutils}/bin/rmdir --ignore-fail-on-non-empty \
        ${escapeShellArg mountPath} ${escapeShellArg "/run/homelab-backups/${volumeId}"} || true
      ${pkgs.coreutils}/bin/rm -f ${escapeShellArg "${lock}/owner"}
      ${pkgs.coreutils}/bin/rmdir ${escapeShellArg lock} || status=$?
      exit "$status"
    '';

  keepOption = name: value: optional (value > 0) "--keep-${name}=${toString value}";
  retentionOptions =
    retention:
    [ "--group-by=host,tags" ]
    ++ keepOption "hourly" retention.hourly
    ++ keepOption "daily" retention.daily
    ++ keepOption "weekly" retention.weekly
    ++ keepOption "monthly" retention.monthly
    ++ keepOption "yearly" retention.yearly;

  mkVolumeBackup =
    volumeId: volume:
    let
      target = targets.${volume.backup.target};
    in
    nameValuePair "homelab-${volumeId}" {
      inherit (target)
        environmentFile
        initialize
        passwordFile
        repository
        ;
      paths = [ (snapshotMountPath volumeId) ];
      timerConfig = {
        OnCalendar = volume.backup.onCalendar;
        RandomizedDelaySec = volume.backup.randomizedDelaySec;
        Persistent = true;
      };
      extraBackupArgs = [
        "--host=${registry.host.name}"
        "--one-file-system"
        "--tag=homelab-volume"
        "--tag=volume:${volumeId}"
        "--tag=uuid:${volume.uuid}"
      ];
      backupPrepareCommand = mkPrepareScript volumeId volume;
      backupCleanupCommand = mkCleanupScript volumeId volume;
      createWrapper = true;
    };

  mkTargetMaintenance =
    targetName: target:
    nameValuePair "homelab-maintenance-${targetName}" {
      inherit (target)
        environmentFile
        initialize
        passwordFile
        repository
        ;
      paths = [ ];
      timerConfig = {
        OnCalendar = target.maintenance.onCalendar;
        RandomizedDelaySec = target.maintenance.randomizedDelaySec;
        Persistent = true;
      };
      pruneOpts = retentionOptions target.retention;
      runCheck = true;
      checkOpts = optional (target.maintenance.readDataSubset != null) "--read-data-subset=${target.maintenance.readDataSubset}";
      createWrapper = true;
    };
in
{
  options.${namespace}.backups = {
    targets = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            repository = mkOption {
              type = types.str;
              description = "Restic repository location.";
            };
            passwordFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Runtime path containing the Restic repository password.";
            };
            environmentFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Runtime environment file containing repository backend credentials.";
            };
            initialize = mkBoolOpt false "Whether Restic may initialize the repository.";
            retention = {
              hourly = mkOpt types.ints.nonnegative 24 "Hourly snapshots to retain.";
              daily = mkOpt types.ints.nonnegative 14 "Daily snapshots to retain.";
              weekly = mkOpt types.ints.nonnegative 8 "Weekly snapshots to retain.";
              monthly = mkOpt types.ints.nonnegative 12 "Monthly snapshots to retain.";
              yearly = mkOpt types.ints.nonnegative 3 "Yearly snapshots to retain.";
            };
            maintenance = {
              onCalendar = mkOpt types.str "weekly" "Repository prune and check schedule.";
              randomizedDelaySec = mkOpt types.str "6h" "Maximum maintenance timer delay.";
              readDataSubset = mkOption {
                type = types.nullOr types.str;
                default = "10%";
                description = "Restic data subset checked per maintenance run; null checks structure only.";
              };
            };
          };
        }
      );
      default = { };
      description = "Named off-host Restic backup targets.";
    };

    onFailure = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "systemd units started when a backup or repository maintenance job fails.";
    };
  };

  config = mkMerge [
    {
      assertions = [
        {
          assertion = missingTargets == [ ];
          message = "Volumes reference missing homelab backup targets: ${concatStringsSep ", " missingTargets}";
        }
      ]
      ++ mapAttrsToList (targetName: target: {
        assertion = target.passwordFile != null || target.environmentFile != null;
        message = "homelab backup target '${targetName}' requires passwordFile or environmentFile.";
      }) targets;
    }

    {
      services.restic.backups = mkMerge [
        (mapAttrs' mkVolumeBackup backedUpVolumes)
        (mapAttrs' mkTargetMaintenance targets)
      ];
    }

    {
      systemd.services = mkMerge (
        mapAttrsToList (volumeId: _volume: {
          "restic-backups-homelab-${volumeId}" = {
            after = [ "homelab-volume-${volumeId}-permissions.service" ];
            requires = [ "homelab-volume-${volumeId}-permissions.service" ];
            inherit (cfg) onFailure;
            path = with pkgs; [
              coreutils
              lvm2
              systemd
              util-linux
            ];
          };
        }) backedUpVolumes
        ++ mapAttrsToList (targetName: _target: {
          "restic-backups-homelab-maintenance-${targetName}".onFailure = cfg.onFailure;
        }) targets
      );
    }
  ];
}
