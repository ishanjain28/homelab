{
  config,
  inputs,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.backups;
  inherit (cfg) groups targets;
  registry = config.system.homelab.registry;
  volumes = config.${namespace}.volumes;
  volumeTool = getExe pkgs.${namespace}.volume;
  restic = getExe pkgs.restic;

  backedUpVolumes = filterAttrs (
    _volumeId: volume: volume.backup.groups != [ ] && registry.services.${volume.ownerService}.enable
  ) volumes;
  groupVolumes =
    groupName:
    mapAttrsToList (volumeId: volume: volume // { id = volumeId; }) (
      filterAttrs (_volumeId: volume: elem groupName volume.backup.groups) backedUpVolumes
    );
  activeGroups = filterAttrs (groupName: _group: groupVolumes groupName != [ ]) groups;
  maintainedTargets = filterAttrs (_targetName: target: target.maintenance != null) targets;

  missingGroups = unique (
    flatten (
      mapAttrsToList (_volumeId: volume: filter (group: !(hasAttr group groups)) volume.backup.groups) backedUpVolumes
    )
  );
  missingTargets = unique (
    mapAttrsToList (_groupName: group: group.target) (
      filterAttrs (_groupName: group: !(hasAttr group.target targets)) groups
    )
  );
  emptyKeepGroups = attrNames (filterAttrs (_groupName: group: keepOptions group.keep == [ ]) groups);

  keepOption = name: value: optional (value > 0) "--keep-${name}=${toString value}";
  keepOptions =
    keep:
    keepOption "last" keep.last
    ++ keepOption "hourly" keep.hourly
    ++ keepOption "daily" keep.daily
    ++ keepOption "weekly" keep.weekly
    ++ keepOption "monthly" keep.monthly
    ++ keepOption "yearly" keep.yearly
    ++ optional (keep.within != null) "--keep-within=${keep.within}";

  secretName = targetName: "homelab-backups-${targetName}-password";
  resticEnvironment = targetName: {
    RESTIC_REPOSITORY = targets.${targetName}.repository;
    RESTIC_PASSWORD_FILE = config.sops.secrets.${secretName targetName}.path;
    RESTIC_CACHE_DIR = "/var/cache/restic/${targetName}";
  };

  mkResticService =
    {
      targetName,
      description,
      script,
      serviceConfig ? { },
    }:
    let
      target = targets.${targetName};
    in
    {
      inherit description;
      script = ''
        ${restic} cat config > /dev/null 2>&1 || ${restic} init
      ''
      + script;
      environment = resticEnvironment targetName;
      inherit (cfg) onFailure;
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = target.requiresMountsFor;
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "2h";
        CacheDirectory = "restic/${targetName}";
        Nice = 19;
        IOSchedulingClass = "idle";
      }
      // serviceConfig;
    };

  mkTimer =
    name: onCalendar: randomizedDelaySec:
    nameValuePair name {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = onCalendar;
        RandomizedDelaySec = randomizedDelaySec;
        Persistent = true;
      };
    };

  backupCommand =
    groupName: volume:
    let
      mount = "/run/homelab-backup/${groupName}/${volume.id}";
    in
    concatStringsSep " " (
      [
        restic
        "backup"
        "--one-file-system"
        "--tag=group:${groupName}"
        "--tag=volume:${volume.id}"
        "--tag=uuid:${volume.uuid}"
      ]
      ++ map (pattern: "--exclude=${escapeShellArg "${mount}/${pattern}"}") volume.backup.exclude
      ++ [ mount ]
    );

  mkGroupRunner =
    groupName: group:
    let
      volumesByOwner = groupBy (volume: volume.ownerService) (groupVolumes groupName);
      runOwner = owner: ownerVolumes: ''
        if ${volumeTool} backup-prepare --group ${groupName} --owner ${owner}; then
          ${concatMapStringsSep "\n" (volume: "${backupCommand groupName volume} || failed=1") ownerVolumes}
        else
          failed=1
        fi
        ${volumeTool} backup-cleanup --group ${groupName} --owner ${owner} || failed=1
      '';
    in
    nameValuePair "homelab-backup-${groupName}" (mkResticService {
      targetName = group.target;
      description = "Run backup group '${groupName}'";
      script = ''
        failed=0
        ${concatStringsSep "\n" (mapAttrsToList runOwner volumesByOwner)}
        ${restic} forget --tag=group:${groupName} --group-by=tags,paths ${concatStringsSep " " (keepOptions group.keep)} || failed=1
        exit "$failed"
      '';
      serviceConfig.ExecStopPost = map (
        owner: "-${volumeTool} backup-cleanup --wait 60 --group ${groupName} --owner ${owner}"
      ) (attrNames volumesByOwner);
    });

  mkMaintenance =
    targetName: target:
    nameValuePair "homelab-backup-maintenance-${targetName}" (mkResticService {
      inherit targetName;
      description = "Prune and check backup target '${targetName}'";
      script = ''
        ${restic} unlock
        ${restic} prune
        ${restic} check ${
          optionalString (target.maintenance.readDataSubset != null) "--read-data-subset=${target.maintenance.readDataSubset}"
        }
      '';
    });

  mkWrapper =
    targetName:
    pkgs.writeShellScriptBin "restic-${targetName}" ''
      ${toShellVars (resticEnvironment targetName)}
      export ${concatStringsSep " " (attrNames (resticEnvironment targetName))}
      exec ${restic} "$@"
    '';

  mkTargetSecrets =
    targetName: target:
    nameValuePair (secretName targetName) {
      sopsFile = "${inputs.self}/${target.passwordSecret}";
      format = "binary";
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
            passwordSecret = mkOption {
              type = types.nonEmptyStr;
              description = "Repository-relative SOPS file containing the Restic repository password.";
            };
            requiresMountsFor = mkOpt (types.listOf types.str) [ ] "Mount points that must be present before this target is used.";
            maintenance = mkOption {
              type = types.nullOr (
                types.submodule {
                  options = {
                    onCalendar = mkOpt types.str "weekly" "Prune and check schedule.";
                    readDataSubset = mkOption {
                      type = types.nullOr types.str;
                      default = "5%";
                      description = "Restic data subset read per check; null checks structure only.";
                    };
                  };
                }
              );
              default = null;
              description = "Prune and check this repository from this host; exactly one host per repository should set it.";
            };
          };
        }
      );
      default = { };
      description = "Named Restic repositories.";
    };

    groups = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            target = mkOption {
              type = types.nonEmptyStr;
              description = "Backup target that receives this group's snapshots.";
            };
            onCalendar = mkOption {
              type = types.str;
              description = "systemd calendar expression for this group's schedule.";
            };
            randomizedDelaySec = mkOpt types.str "0" "Maximum timer delay added to each run.";
            keep = {
              last = mkOpt types.ints.unsigned 0 "Most recent snapshots to retain per volume.";
              hourly = mkOpt types.ints.unsigned 0 "Hourly snapshots to retain per volume.";
              daily = mkOpt types.ints.unsigned 0 "Daily snapshots to retain per volume.";
              weekly = mkOpt types.ints.unsigned 0 "Weekly snapshots to retain per volume.";
              monthly = mkOpt types.ints.unsigned 0 "Monthly snapshots to retain per volume.";
              yearly = mkOpt types.ints.unsigned 0 "Yearly snapshots to retain per volume.";
              within = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Restic duration within which every snapshot is retained, such as 30d or 1y2m.";
              };
            };
          };
        }
      );
      default = { };
      description = "Backup groups: a schedule and retention policy that volumes opt into.";
    };

    onFailure = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "systemd units started when a backup or maintenance job fails.";
    };
  };

  config = {
    assertions = [
      {
        assertion = missingGroups == [ ];
        message = "Volumes reference missing homelab backup groups: ${concatStringsSep ", " missingGroups}";
      }
      {
        assertion = missingTargets == [ ];
        message = "Backup groups reference missing homelab backup targets: ${concatStringsSep ", " missingTargets}";
      }
      {
        assertion = emptyKeepGroups == [ ];
        message = "Backup groups must retain at least one snapshot: ${concatStringsSep ", " emptyKeepGroups}";
      }
    ];

    sops.secrets = mapAttrs' mkTargetSecrets targets;
    environment.systemPackages = [ pkgs.restic ] ++ map mkWrapper (attrNames targets);

    systemd.services = (mapAttrs' mkGroupRunner activeGroups) // (mapAttrs' mkMaintenance maintainedTargets);
    systemd.timers =
      (mapAttrs' (
        groupName: group: mkTimer "homelab-backup-${groupName}" group.onCalendar group.randomizedDelaySec
      ) activeGroups)
      // (mapAttrs' (
        targetName: target: mkTimer "homelab-backup-maintenance-${targetName}" target.maintenance.onCalendar "0"
      ) maintainedTargets);
  };
}
