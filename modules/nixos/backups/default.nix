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
  volumePackage = pkgs.callPackage ../../../packages/volume { };

  backedUpVolumes = filterAttrs (_volumeId: volume: volume.backup != null) volumes;
  backedUpVolumeList = mapAttrsToList (volumeId: volume: volume // { inherit volumeId; }) backedUpVolumes;
  backupGroups = groupBy (volume: volume.ownerService) backedUpVolumeList;
  activeBackupGroups = filterAttrs (ownerService: _group: services.${ownerService}.enable) backupGroups;

  missingTargets = unique (
    mapAttrsToList (_volumeId: volume: volume.backup.target) (
      filterAttrs (_volumeId: volume: !(hasAttr volume.backup.target targets)) backedUpVolumes
    )
  );
  inconsistentGroups = attrNames (
    filterAttrs (
      _ownerService: group:
      let
        expected = (head group).backup;
      in
      any (volume: volume.backup != expected) (tail group)
    ) backupGroups
  );

  keepOption = name: value: optional (value > 0) "--keep-${name}=${toString value}";
  retentionOptions =
    retention:
    # Operation IDs are intentionally unique Restic tags, so grouping by tags
    # would make every snapshot its own retention group and retain everything.
    [ "--group-by=host,paths" ]
    ++ keepOption "hourly" retention.hourly
    ++ keepOption "daily" retention.daily
    ++ keepOption "weekly" retention.weekly
    ++ keepOption "monthly" retention.monthly
    ++ keepOption "yearly" retention.yearly;

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

  volumeUnit = volumeId: "homelab-volume-${volumeId}-permissions.service";
  backupUnit = ownerService: "homelab-backup-${ownerService}";
  mkBackupService =
    ownerService: group:
    let
      dependencies = map (volume: volumeUnit volume.volumeId) group;
    in
    nameValuePair (backupUnit ownerService) {
      description = "Back up volumes owned by '${ownerService}'";
      after = dependencies;
      requires = dependencies;
      inherit (cfg) onFailure;
      path = with pkgs; [
        coreutils
        e2fsprogs
        lvm2
        restic
        systemd
        util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${volumePackage}/bin/volume backup ${escapeShellArg ownerService}";
        ExecStopPost = "${volumePackage}/bin/volume reconcile --owner-service ${escapeShellArg ownerService}";
        TimeoutStartSec = "infinity";
      };
    };

  mkCron =
    ownerService: group:
    "${(head group).backup.cron} root ${pkgs.systemd}/bin/systemctl start ${backupUnit ownerService}.service";
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
        {
          assertion = inconsistentGroups == [ ];
          message = "Volumes owned by one service are snapshotted together and must use the same backup target and cron: ${concatStringsSep ", " inconsistentGroups}";
        }
      ]
      ++ mapAttrsToList (targetName: target: {
        assertion = target.passwordFile != null || target.environmentFile != null;
        message = "Homelab backup target '${targetName}' requires passwordFile or environmentFile.";
      }) targets;
    }

    {
      services.restic.backups = mapAttrs' mkTargetMaintenance targets;
      services.cron = mkIf (activeBackupGroups != { }) {
        enable = true;
        systemCronJobs = mapAttrsToList mkCron activeBackupGroups;
      };
      environment.systemPackages = optional (targets != { }) pkgs.restic;
    }

    {
      systemd.services = (mapAttrs' mkBackupService activeBackupGroups) // {
        homelab-volume-reconcile = {
          description = "Reconcile interrupted homelab volume operations";
          wantedBy = [ "multi-user.target" ];
          before = map (ownerService: "${backupUnit ownerService}.service") (attrNames activeBackupGroups);
          path = with pkgs; [
            coreutils
            lvm2
            systemd
            util-linux
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${volumePackage}/bin/volume reconcile";
          };
        };
      };
    }

    {
      systemd.services = mkMerge (
        mapAttrsToList (targetName: _target: {
          "restic-backups-homelab-maintenance-${targetName}".onFailure = cfg.onFailure;
        }) targets
      );
    }
  ];
}
