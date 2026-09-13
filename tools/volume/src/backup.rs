use crate::lock::VolumeLocks;
use crate::models::{load_state, BackupPolicy, State, Volume};
use crate::operation::{list_operations, new_operation_id, Operation, OperationVolume};
use crate::restic;
use std::fs;
use std::fs::OpenOptions;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

const BACKUP_ROOT: &str = "/run/homelab-volume/backup";
const MIGRATION_BLOCK_ROOT: &str = "/var/lib/homelab-volume/migration-block";
const SNAPSHOT_EXTENTS: &str = "20%ORIGIN";

pub fn run_backup(
    state_file: &Path,
    owner_service: &str,
    final_backup: bool,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let volumes = backup_volumes(&state, owner_service)?;
    let existing_block = migration_block_path(owner_service);
    if existing_block.exists() {
        let blocker = fs::read_to_string(&existing_block)
            .map_err(|error| format!("failed to read {}: {error}", existing_block.display()))?;
        if final_backup {
            return Err(format!(
                "source service {owner_service:?} is already blocked by migration operation {:?}",
                blocker.trim()
            ));
        }
        println!(
            "skipping backup for {owner_service:?}: migration operation {:?} holds the source start block",
            blocker.trim()
        );
        return Ok(());
    }
    if final_backup {
        let omitted = state
            .volumes
            .values()
            .filter(|volume| volume.owner_service == owner_service && volume.backup.is_none())
            .map(|volume| volume.id.clone())
            .collect::<Vec<_>>();
        if !omitted.is_empty() {
            return Err(format!(
                "final migration export requires every volume owned by {owner_service:?} to have a backup policy; missing: {}",
                omitted.join(", ")
            ));
        }
    }
    if final_backup && volumes.iter().any(|volume| !volume.owner_enabled) {
        return Err(format!(
            "final migration export requires source service {owner_service:?} to be enabled in the deployed configuration"
        ));
    }
    let policy = common_policy(&volumes)?;
    let target = state.backup_targets.get(&policy.target).ok_or_else(|| {
        format!(
            "backup target {:?} used by {owner_service:?} is not declared",
            policy.target
        )
    })?;
    // Validate credentials and repository reachability before stopping the
    // owner service. Initialization is opt-in on the target declaration.
    restic::ensure_repository(target)?;
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let operation_id = new_operation_id("backup")?;
    let _locks = VolumeLocks::acquire(&ids, &format!("backup:{operation_id}"))?;

    reconcile_volumes(&volumes)?;

    let owner_was_active = service_is_active(&volumes[0].owner_unit)?;
    let mut operation = Operation {
        schema_version: 1,
        id: operation_id.clone(),
        kind: if final_backup {
            "migration-backup".to_string()
        } else {
            "backup".to_string()
        },
        phase: "stopping-owner".to_string(),
        owner_service: owner_service.to_string(),
        owner_was_active,
        source_host: Some(state.host.clone()),
        snapshot_id: None,
        target: policy.target.clone(),
        volumes: volumes
            .iter()
            .map(|volume| OperationVolume {
                id: volume.id.clone(),
                active_name: volume.name.clone(),
                uuid: volume.uuid.clone(),
                fs_type: volume.fs_type.clone(),
                staging_name: String::new(),
                rollback_name: String::new(),
                failed_name: String::new(),
                had_active: false,
            })
            .collect(),
        completed_volumes: Vec::new(),
    };
    operation.save()?;

    let mut migration_block_created = false;
    let result = (|| {
        if final_backup {
            create_migration_block(owner_service, &operation_id)?;
            migration_block_created = true;
        }
        if owner_was_active {
            systemctl("stop", &volumes[0].owner_unit)?;
        }

        run("sync", &[])?;
        operation.phase = "creating-snapshots".to_string();
        operation.save()?;

        for volume in &volumes {
            create_snapshot(volume)?;
        }

        if owner_was_active && !final_backup {
            systemctl("start", &volumes[0].owner_unit)?;
        }

        operation.phase = "mounting-snapshots".to_string();
        operation.save()?;
        for volume in &volumes {
            mount_snapshot(volume)?;
        }

        operation.phase = "uploading".to_string();
        operation.save()?;
        let mut command = restic::command(target)?;
        command.arg("backup");
        command.args(["--host", &state.host]);
        command.arg("--one-file-system");
        command.args(["--tag", "homelab-volume"]);
        command.args(["--tag", &format!("owner:{owner_service}")]);
        command.args(["--tag", &format!("operation:{operation_id}")]);
        if final_backup {
            command.args(["--tag", "migration-final"]);
        }
        for volume in &volumes {
            command.args(["--tag", &format!("volume:{}", volume.id)]);
            command.args(["--tag", &format!("uuid:{}", volume.uuid)]);
            command.arg(backup_mount_path(volume));
        }
        run_backup_command(&mut command, &volumes)?;

        let snapshots = restic::snapshots(
            target,
            &[format!("operation:{operation_id}")],
            Some(&state.host),
        )?;
        let snapshot = snapshots
            .into_iter()
            .max_by(|left, right| left.time.cmp(&right.time))
            .ok_or_else(|| format!("Restic created no snapshot for operation {operation_id}"))?;
        operation.snapshot_id = Some(snapshot.id);
        operation.phase = "uploaded".to_string();
        operation.save()?;
        Ok(())
    })();

    // A successful final migration backup is the source write boundary. Keep
    // the source stopped. If the upload failed, restore its prior availability.
    let restart_owner = owner_was_active && (!final_backup || result.is_err());
    let cleanup = cleanup_backup(
        &volumes,
        restart_owner,
        (migration_block_created && result.is_err())
            .then_some((owner_service, operation_id.as_str())),
    );
    match (result, cleanup) {
        (Ok(()), Ok(())) => {
            operation.phase = "complete".to_string();
            operation.save()?;
            if final_backup {
                println!(
                    "operation={} snapshot={} source-service=stopped",
                    operation.id,
                    operation.snapshot_id.as_deref().unwrap_or("unknown")
                );
            } else {
                println!("{}", operation.id);
            }
            Ok(())
        }
        (Err(error), Ok(())) => {
            operation.phase = "failed".to_string();
            let _ = operation.save();
            Err(error)
        }
        (Ok(()), Err(cleanup_error)) => {
            operation.phase = "cleanup-failed".to_string();
            let _ = operation.save();
            Err(cleanup_error)
        }
        (Err(error), Err(cleanup_error)) => {
            operation.phase = "cleanup-failed".to_string();
            let _ = operation.save();
            Err(format!("{error}\ncleanup also failed: {cleanup_error}"))
        }
    }
}

pub fn run_migration_cancel(
    state_file: &Path,
    operation_id: &str,
    assume_yes: bool,
) -> Result<(), String> {
    change_migration_block(state_file, operation_id, assume_yes, true)
}

pub fn run_migration_release(
    state_file: &Path,
    operation_id: &str,
    assume_yes: bool,
) -> Result<(), String> {
    change_migration_block(state_file, operation_id, assume_yes, false)
}

fn change_migration_block(
    state_file: &Path,
    operation_id: &str,
    assume_yes: bool,
    restart_source: bool,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let mut operation = crate::operation::load_operation(operation_id)?;
    if operation.kind != "migration-backup" || operation.phase != "complete" {
        return Err(format!(
            "operation {operation_id} is not a completed migration export"
        ));
    }
    let volumes = backup_volumes(&state, &operation.owner_service)?;
    let declaration_changed = volumes.len() != operation.volumes.len()
        || volumes.iter().any(|volume| {
            !operation.volumes.iter().any(|entry| {
                entry.id == volume.id
                    && entry.active_name == volume.name
                    && entry.uuid == volume.uuid
                    && entry.fs_type == volume.fs_type
            })
        });
    if declaration_changed {
        return Err(format!(
            "volume declarations changed since operation {operation_id} was created"
        ));
    }
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let _locks = VolumeLocks::acquire(&ids, &format!("migration-source:{operation_id}"))?;
    if restart_source && volumes.iter().any(|volume| !volume.owner_enabled) {
        return Err(format!(
            "source service {:?} is disabled in the deployed configuration; refusing to restart it",
            operation.owner_service
        ));
    }
    if !restart_source && volumes.iter().any(|volume| volume.owner_enabled) {
        return Err(format!(
            "disable source service {:?} in the deployed configuration before releasing its migration block",
            operation.owner_service
        ));
    }
    let action = if restart_source {
        "cancel the migration and restart the source service"
    } else {
        "release the stopped source after completing the migration"
    };
    if !assume_yes && !crate::prompt::confirm(action)? {
        return Err(format!("{action}: skipped"));
    }
    remove_migration_block(&operation.owner_service, operation_id)?;
    if restart_source {
        systemctl("start", &volumes[0].owner_unit)?;
        operation.phase = "canceled".to_string();
    } else {
        operation.phase = "released".to_string();
    }
    operation.save()
}

fn run_backup_command(command: &mut Command, volumes: &[Volume]) -> Result<(), String> {
    let mut child = command
        .spawn()
        .map_err(|error| format!("failed to execute restic: {error}"))?;
    loop {
        if let Some(status) = child
            .try_wait()
            .map_err(|error| format!("failed to wait for restic: {error}"))?
        {
            return if status.success() {
                Ok(())
            } else {
                Err(format!("restic failed with {status}"))
            };
        }
        for volume in volumes {
            if let Err(error) = validate_snapshot_health(volume) {
                let _ = child.kill();
                let _ = child.wait();
                return Err(error);
            }
        }
        thread::sleep(Duration::from_secs(5));
    }
}

fn validate_snapshot_health(volume: &Volume) -> Result<(), String> {
    let snapshot = snapshot_path(volume)?;
    let value = output(
        "lvs",
        &[
            "--noheadings",
            "--options",
            "data_percent",
            snapshot.to_string_lossy().as_ref(),
        ],
    )?;
    let percent = value.trim().parse::<f64>().map_err(|error| {
        format!(
            "failed to read COW usage for {}: {error}",
            snapshot.display()
        )
    })?;
    if percent >= 95.0 {
        Err(format!(
            "[{}] snapshot COW reserve reached {percent:.1}%; aborting before overflow",
            volume.id
        ))
    } else {
        Ok(())
    }
}

pub fn run_reconcile(state_file: &Path, owner_service: Option<&str>) -> Result<(), String> {
    let state = load_state(state_file)?;
    let volumes = state
        .volumes
        .values()
        .filter(|volume| owner_service.is_none_or(|owner| volume.owner_service == owner))
        .cloned()
        .collect::<Vec<_>>();
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let _locks = VolumeLocks::acquire(&ids, "reconcile")?;
    reconcile_volumes(&volumes)?;
    recover_interrupted_backups(&state, owner_service)
}

fn recover_interrupted_backups(state: &State, requested_owner: Option<&str>) -> Result<(), String> {
    for mut operation in list_operations()? {
        if !matches!(operation.kind.as_str(), "backup" | "migration-backup")
            || matches!(
                operation.phase.as_str(),
                "complete" | "failed" | "reconciled" | "canceled" | "released"
            )
            || requested_owner.is_some_and(|owner| owner != operation.owner_service)
        {
            continue;
        }
        let missing = operation
            .volumes
            .iter()
            .filter(|entry| !state.volumes.contains_key(&entry.id))
            .map(|entry| entry.id.clone())
            .collect::<Vec<_>>();
        if !missing.is_empty() {
            return Err(format!(
                "cannot reconcile operation {} because its volume declarations were removed: {}",
                operation.id,
                missing.join(", ")
            ));
        }
        let owner_volume = state
            .volumes
            .values()
            .find(|volume| volume.owner_service == operation.owner_service);
        if operation.kind == "migration-backup" {
            remove_migration_block(&operation.owner_service, &operation.id)?;
        }
        if operation.owner_was_active {
            if let Some(volume) = owner_volume {
                if volume.owner_enabled && !service_is_active(&volume.owner_unit)? {
                    systemctl("start", &volume.owner_unit)?;
                }
            }
        }
        operation.phase = "reconciled".to_string();
        operation.save()?;
    }
    Ok(())
}

pub fn backup_volumes(state: &State, owner_service: &str) -> Result<Vec<Volume>, String> {
    let all = state
        .volumes
        .values()
        .filter(|volume| volume.owner_service == owner_service)
        .cloned()
        .collect::<Vec<_>>();
    if all.is_empty() {
        return Err(format!(
            "service {owner_service:?} owns no declared volumes"
        ));
    }
    let volumes = all
        .into_iter()
        .filter(|volume| volume.backup.is_some())
        .collect::<Vec<_>>();
    if volumes.is_empty() {
        return Err(format!(
            "service {owner_service:?} has no volumes opted into backup"
        ));
    }
    common_policy(&volumes)?;
    Ok(volumes)
}

pub fn common_policy(volumes: &[Volume]) -> Result<BackupPolicy, String> {
    let first = volumes
        .first()
        .and_then(|volume| volume.backup.clone())
        .ok_or_else(|| "backup group is empty".to_string())?;
    let mismatched = volumes
        .iter()
        .filter(|volume| volume.backup.as_ref() != Some(&first))
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    if mismatched.is_empty() {
        Ok(first)
    } else {
        Err(format!(
            "volumes owned by one service are snapshotted together and must use the same target and cron; mismatched volumes: {}",
            mismatched.join(", ")
        ))
    }
}

fn create_snapshot(volume: &Volume) -> Result<(), String> {
    let name = snapshot_name(volume)?;
    run(
        "lvcreate",
        &[
            "--yes",
            "--snapshot",
            "--extents",
            SNAPSHOT_EXTENTS,
            "--addtag",
            "homelab-backup",
            "--addtag",
            &format!("homelab-volume-{}", volume.id),
            "--name",
            &name,
            &volume.lv,
        ],
    )?;
    run("udevadm", &["settle"])
}

fn mount_snapshot(volume: &Volume) -> Result<(), String> {
    let mount_path = backup_mount_path(volume);
    fs::create_dir_all(&mount_path)
        .map_err(|error| format!("failed to create {}: {error}", mount_path.display()))?;
    run(
        "mount",
        &[
            "--types",
            &volume.fs_type,
            "--options",
            "ro,noload",
            &snapshot_path(volume)?.to_string_lossy(),
            &mount_path.to_string_lossy(),
        ],
    )
}

fn cleanup_backup(
    volumes: &[Volume],
    restart_owner: bool,
    migration_block: Option<(&str, &str)>,
) -> Result<(), String> {
    let mut errors = Vec::new();
    for volume in volumes.iter().rev() {
        if let Err(error) = cleanup_volume(volume) {
            errors.push(error);
        }
    }
    if let Some((owner_service, operation_id)) = migration_block {
        if let Err(error) = remove_migration_block(owner_service, operation_id) {
            errors.push(error);
        }
    }
    if restart_owner {
        match service_is_active(&volumes[0].owner_unit) {
            Ok(false) => {
                if let Err(error) = systemctl("start", &volumes[0].owner_unit) {
                    errors.push(error);
                }
            }
            Err(error) => errors.push(error),
            Ok(true) => {}
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("\n"))
    }
}

fn migration_block_path(owner_service: &str) -> PathBuf {
    Path::new(MIGRATION_BLOCK_ROOT).join(owner_service)
}

fn create_migration_block(owner_service: &str, operation_id: &str) -> Result<(), String> {
    fs::create_dir_all(MIGRATION_BLOCK_ROOT)
        .map_err(|error| format!("failed to create {MIGRATION_BLOCK_ROOT}: {error}"))?;
    let path = migration_block_path(owner_service);
    if path.exists() {
        let existing = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        return Err(format!(
            "source service {owner_service:?} is already blocked by migration operation {:?}",
            existing.trim()
        ));
    }
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&path)
        .map_err(|error| format!("failed to create {}: {error}", path.display()))?;
    writeln!(file, "{operation_id}")
        .map_err(|error| format!("failed to write {}: {error}", path.display()))?;
    file.sync_all()
        .map_err(|error| format!("failed to sync {}: {error}", path.display()))?;
    sync_directory(Path::new(MIGRATION_BLOCK_ROOT))
}

fn remove_migration_block(owner_service: &str, operation_id: &str) -> Result<(), String> {
    let path = migration_block_path(owner_service);
    if !path.exists() {
        return Ok(());
    }
    let existing = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    if existing.trim() != operation_id {
        return Err(format!(
            "refusing to remove {}: it belongs to operation {:?}, not {operation_id:?}",
            path.display(),
            existing.trim()
        ));
    }
    fs::remove_file(&path)
        .map_err(|error| format!("failed to remove {}: {error}", path.display()))?;
    sync_directory(Path::new(MIGRATION_BLOCK_ROOT))
}

fn sync_directory(path: &Path) -> Result<(), String> {
    let directory = fs::File::open(path)
        .map_err(|error| format!("failed to open {} for sync: {error}", path.display()))?;
    directory
        .sync_all()
        .map_err(|error| format!("failed to sync {}: {error}", path.display()))
}

fn reconcile_volumes(volumes: &[Volume]) -> Result<(), String> {
    let mut errors = Vec::new();
    for volume in volumes {
        if let Err(error) = cleanup_volume(volume) {
            errors.push(error);
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("\n"))
    }
}

fn cleanup_volume(volume: &Volume) -> Result<(), String> {
    let mount_path = backup_mount_path(volume);
    if is_mountpoint(&mount_path)? {
        run("umount", &[&mount_path.to_string_lossy()])?;
    }
    if mount_path.exists() {
        fs::remove_dir(&mount_path)
            .map_err(|error| format!("failed to remove {}: {error}", mount_path.display()))?;
    }

    let snapshot = snapshot_path(volume)?;
    let snapshot_name = snapshot_name(volume)?;
    if lv_exists(&snapshot_name)? {
        let origin = output(
            "lvs",
            &[
                "--noheadings",
                "--options",
                "origin",
                &snapshot.to_string_lossy(),
            ],
        )?;
        if origin.trim() != volume.name {
            return Err(format!(
                "refusing to remove {}: expected origin {}, got {}",
                snapshot.display(),
                volume.name,
                origin.trim()
            ));
        }
        let tags = output(
            "lvs",
            &[
                "--noheadings",
                "--options",
                "lv_tags",
                &snapshot.to_string_lossy(),
            ],
        )?;
        if !tags.split(',').any(|tag| tag.trim() == "homelab-backup") {
            return Err(format!(
                "refusing to remove {}: expected LVM tag homelab-backup is missing",
                snapshot.display()
            ));
        }
        run("lvremove", &["--yes", &snapshot.to_string_lossy()])?;
    }
    Ok(())
}

fn lv_exists(name: &str) -> Result<bool, String> {
    let status = Command::new("lvs")
        .args(["--noheadings", &format!("pool/{name}")])
        .status()
        .map_err(|error| format!("failed to query LV {name}: {error}"))?;
    match status.code() {
        Some(0) => Ok(true),
        Some(5) => Ok(false),
        _ => Err(format!("lvs failed while querying {name}: {status}")),
    }
}

fn snapshot_name(volume: &Volume) -> Result<String, String> {
    let name = format!("{}-backup", volume.name);
    if name.len() <= 127 {
        Ok(name)
    } else {
        Err(format!("snapshot name is too long: {name}"))
    }
}

fn snapshot_path(volume: &Volume) -> Result<PathBuf, String> {
    let parent = Path::new(&volume.lv)
        .parent()
        .ok_or_else(|| format!("invalid LV path {}", volume.lv))?;
    Ok(parent.join(snapshot_name(volume)?))
}

pub fn backup_mount_path(volume: &Volume) -> PathBuf {
    Path::new(BACKUP_ROOT).join(&volume.id)
}

fn service_is_active(unit: &str) -> Result<bool, String> {
    let status = Command::new("systemctl")
        .args(["is-active", "--quiet", unit])
        .status()
        .map_err(|error| format!("failed to query {unit}: {error}"))?;
    match status.code() {
        Some(0) => Ok(true),
        Some(3) => Ok(false),
        _ => Err(format!("systemctl is-active {unit} failed with {status}")),
    }
}

fn systemctl(action: &str, unit: &str) -> Result<(), String> {
    run("systemctl", &[action, unit])
}

fn is_mountpoint(path: &Path) -> Result<bool, String> {
    if !path.exists() {
        return Ok(false);
    }
    let status = Command::new("mountpoint")
        .args(["--quiet", &path.to_string_lossy()])
        .status()
        .map_err(|error| format!("failed to inspect {}: {error}", path.display()))?;
    match status.code() {
        Some(0) => Ok(true),
        Some(1) => Ok(false),
        _ => Err(format!(
            "mountpoint failed for {}: {status}",
            path.display()
        )),
    }
}

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(program)
        .args(args)
        .status()
        .map_err(|error| format!("failed to execute {program}: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{program} failed with {status}"))
    }
}

fn output(program: &str, args: &[&str]) -> Result<String, String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| format!("failed to execute {program}: {error}"))?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        Err(format!(
            "{program} failed with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        ))
    }
}
