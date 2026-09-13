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
  services = config.system.homelab.registry.services;
  inherit (cfg) targets;

  backedUpVolumes = filterAttrs (
    _volumeId: volume: volume.backup != null && services.${volume.ownerService}.enable
  ) volumes;
  missingTargets = unique (
    mapAttrsToList (_volumeId: volume: volume.backup.target) (
      filterAttrs (_volumeId: volume: !(hasAttr volume.backup.target targets)) backedUpVolumes
    )
  );

  keepOption = name: value: optional (value > 0) "--keep-${name}=${toString value}";
  retentionOptions =
    retention:
    [ "--group-by=host,paths" ]
    ++ keepOption "hourly" retention.hourly
    ++ keepOption "daily" retention.daily
    ++ keepOption "weekly" retention.weekly
    ++ keepOption "monthly" retention.monthly
    ++ keepOption "yearly" retention.yearly;

  volumeBackupName = volumeId: "homelab-volume-${volumeId}";
  volumeMountUnit = volume: "var-lib-volumes-${replaceStrings [ "-" ] [ "\\x2d" ] volume.name}.mount";
  volumePath = volume: "/var/lib/volumes/${volume.name}";

  mkVolumeBackup =
    volumeId: volume:
    let
      target = targets.${volume.backup.target};
    in
    nameValuePair (volumeBackupName volumeId) {
      inherit (target)
        environmentFile
        initialize
        passwordFile
        repository
        ;
      paths = [ (volumePath volume) ];
      timerConfig = { };
      createWrapper = true;
    };

  mkVolumeBackupOrdering = volumeId: volume: {
    "restic-backups-${volumeBackupName volumeId}" = {
      after = [ (volumeMountUnit volume) ];
      requires = [ (volumeMountUnit volume) ];
      inherit (cfg) onFailure;
    };
  };

  mkCron =
    volumeId: volume:
    "${volume.backup.cron} root ${pkgs.systemd}/bin/systemctl start restic-backups-${volumeBackupName volumeId}.service";

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
      checkOpts = optional (
        target.maintenance.readDataSubset != null
      ) "--read-data-subset=${target.maintenance.readDataSubset}";
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
              type = types.nonEmptyStr;
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
              hourly = mkOpt types.ints.unsigned 24 "Hourly snapshots to retain.";
              daily = mkOpt types.ints.unsigned 14 "Daily snapshots to retain.";
              weekly = mkOpt types.ints.unsigned 8 "Weekly snapshots to retain.";
              monthly = mkOpt types.ints.unsigned 12 "Monthly snapshots to retain.";
              yearly = mkOpt types.ints.unsigned 3 "Yearly snapshots to retain.";
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
        message = "Homelab backup target '${targetName}' requires passwordFile or environmentFile.";
      }) targets;
    }

    {
      services.restic.backups = (mapAttrs' mkVolumeBackup backedUpVolumes) // (mapAttrs' mkTargetMaintenance targets);
      services.cron = mkIf (backedUpVolumes != { }) {
        enable = true;
        systemCronJobs = mapAttrsToList mkCron backedUpVolumes;
      };
      environment.systemPackages = optional (targets != { }) pkgs.restic;
    }

    {
      systemd.services = mkMerge (
        mapAttrsToList mkVolumeBackupOrdering backedUpVolumes
        ++ mapAttrsToList (targetName: _target: {
          "restic-backups-homelab-maintenance-${targetName}".onFailure = cfg.onFailure;
        }) targets
      );
    }
  ];
}
