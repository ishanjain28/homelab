use crate::backup::{backup_mount_path, backup_volumes, common_policy};
use crate::lock::VolumeLocks;
use crate::models::{load_state, State, Volume};
use crate::operation::{load_operation, new_operation_id, Operation, OperationVolume};
use crate::prompt::confirm;
use crate::restic::{self, ResticSnapshot};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const RESTORE_ROOT: &str = "/run/homelab-volume/restore";
const VG_NAME: &str = "pool";

pub fn run_restore_list(
    state_file: &Path,
    owner_service: &str,
    source_host: Option<&str>,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let volumes = complete_service_backup(&state, owner_service)?;
    let policy = common_policy(&volumes)?;
    let target = state
        .backup_targets
        .get(&policy.target)
        .ok_or_else(|| format!("backup target {:?} is not declared", policy.target))?;
    let snapshots = eligible_snapshots(target, &volumes, owner_service, source_host, None)?;
    for snapshot in snapshots {
        println!(
            "{}\t{}\t{}\t{}",
            snapshot.id,
            snapshot.time,
            snapshot.hostname,
            snapshot.tags.join(",")
        );
    }
    Ok(())
}

pub fn run_restore_prepare(
    state_file: &Path,
    owner_service: &str,
    source_host: Option<&str>,
    requested_snapshot: Option<&str>,
    assume_yes: bool,
) -> Result<(), String> {
    run_prepare(
        state_file,
        owner_service,
        source_host,
        requested_snapshot,
        assume_yes,
        "restore",
        None,
    )
}

pub fn run_migration_prepare(
    state_file: &Path,
    owner_service: &str,
    source_host: &str,
    requested_snapshot: &str,
    assume_yes: bool,
) -> Result<(), String> {
    run_prepare(
        state_file,
        owner_service,
        Some(source_host),
        Some(requested_snapshot),
        assume_yes,
        "migration",
        Some("migration-final"),
    )
}

#[allow(clippy::too_many_arguments)]
fn run_prepare(
    state_file: &Path,
    owner_service: &str,
    source_host: Option<&str>,
    requested_snapshot: Option<&str>,
    assume_yes: bool,
    kind: &str,
    required_tag: Option<&str>,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let volumes = complete_service_backup(&state, owner_service)?;
    require_staging_owner(&volumes)?;
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let operation_id = new_operation_id(kind)?;
    let _locks = VolumeLocks::acquire(&ids, &format!("{kind}:{operation_id}"))?;
    let policy = common_policy(&volumes)?;
    let target = state
        .backup_targets
        .get(&policy.target)
        .ok_or_else(|| format!("backup target {:?} is not declared", policy.target))?;
    let snapshots = eligible_snapshots(target, &volumes, owner_service, source_host, required_tag)?;
    let snapshot = select_snapshot(snapshots, requested_snapshot)?;

    let mut operation = Operation {
        schema_version: 1,
        id: operation_id.clone(),
        kind: kind.to_string(),
        phase: "planned".to_string(),
        owner_service: owner_service.to_string(),
        owner_was_active: false,
        source_host: Some(snapshot.hostname.clone()),
        snapshot_id: Some(snapshot.id.clone()),
        target: policy.target,
        volumes: volumes
            .iter()
            .map(|volume| OperationVolume {
                id: volume.id.clone(),
                active_name: volume.name.clone(),
                uuid: volume.uuid.clone(),
                fs_type: volume.fs_type.clone(),
                staging_name: derived_lv_name(&volume.name, "restore", &operation_id),
                rollback_name: derived_lv_name(&volume.name, "rollback", &operation_id),
                failed_name: derived_lv_name(&volume.name, "failed", &operation_id),
                had_active: false,
            })
            .collect(),
        completed_volumes: Vec::new(),
    };
    operation.save()?;

    let prompt = format!(
        "{kind} service {owner_service:?} from Restic snapshot {} on {} into new staging LVs",
        snapshot.id, snapshot.hostname,
    );
    if !assume_yes && !confirm(&prompt)? {
        return Err(format!("{prompt}: skipped"));
    }

    operation.phase = "restoring".to_string();
    operation.save()?;
    for (volume, operation_volume) in volumes.iter().zip(&operation.volumes) {
        prepare_staging_volume(volume, operation_volume, &operation.id)?;

        if let Err(error) = restore_one(
            target,
            &snapshot.id,
            &operation.id,
            volume,
            operation_volume,
        ) {
            operation.phase = "failed".to_string();
            let _ = operation.save();
            return Err(error);
        }
        operation.completed_volumes.push(volume.id.clone());
        operation.save()?;
    }

    operation.completed_volumes.clear();
    operation.phase = "ready-for-cutover".to_string();
    operation.save()?;
    println!("{}", operation.id);
    Ok(())
}

pub fn run_restore_resume(state_file: &Path, operation_id: &str) -> Result<(), String> {
    let state = load_state(state_file)?;
    let mut operation = load_operation(operation_id)?;
    if !matches!(operation.kind.as_str(), "restore" | "migration")
        || !matches!(operation.phase.as_str(), "restoring" | "failed")
    {
        return Err(format!(
            "operation {operation_id} is not an interrupted restore or migration (kind {:?}, phase {:?})",
            operation.kind, operation.phase
        ));
    }
    let volumes = operation_volumes(&state, &operation)?;
    require_staging_owner(&volumes)?;
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let _locks = VolumeLocks::acquire(&ids, &format!("restore-resume:{operation_id}"))?;
    let target = state
        .backup_targets
        .get(&operation.target)
        .ok_or_else(|| format!("backup target {:?} is not declared", operation.target))?;
    let snapshot_id = operation
        .snapshot_id
        .clone()
        .ok_or_else(|| format!("operation {operation_id} has no Restic snapshot ID"))?;

    operation.phase = "restoring".to_string();
    operation.save()?;
    for (index, volume) in volumes.iter().enumerate() {
        if operation.completed_volumes.contains(&volume.id) {
            continue;
        }
        let operation_volume = &operation.volumes[index];
        if !lv_exists(&operation_volume.staging_name)? {
            prepare_staging_volume(volume, operation_volume, &operation.id)?;
        }
        if let Err(error) = restore_one(
            target,
            &snapshot_id,
            &operation.id,
            volume,
            operation_volume,
        ) {
            operation.phase = "failed".to_string();
            let _ = operation.save();
            return Err(error);
        }
        operation.completed_volumes.push(volume.id.clone());
        operation.save()?;
    }
    operation.completed_volumes.clear();
    operation.phase = "ready-for-cutover".to_string();
    operation.save()?;
    println!("operation {operation_id} is ready for cutover");
    Ok(())
}

pub fn run_restore_cutover(
    state_file: &Path,
    operation_id: &str,
    assume_yes: bool,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let mut operation = load_operation(operation_id)?;
    if !matches!(operation.kind.as_str(), "restore" | "migration") {
        return Err(format!(
            "operation {operation_id} is not a restore or migration"
        ));
    }
    if !matches!(
        operation.phase.as_str(),
        "ready-for-cutover" | "cutting-over" | "cutover-failed"
    ) {
        return Err(format!(
            "operation {operation_id} is in phase {:?}, not ready for cutover",
            operation.phase
        ));
    }
    let volumes = operation_volumes(&state, &operation)?;
    require_staging_owner(&volumes)?;
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let _locks = VolumeLocks::acquire(&ids, &format!("cutover:{operation_id}"))?;
    let prompt = format!(
        "replace the active LV names for service {:?}; existing LVs will be retained as rollback copies",
        operation.owner_service
    );
    if !assume_yes && !confirm(&prompt)? {
        return Err(format!("{prompt}: skipped"));
    }

    operation.phase = "cutting-over".to_string();
    operation.save()?;
    for (index, volume) in volumes.iter().enumerate() {
        if operation.completed_volumes.contains(&volume.id) {
            continue;
        }
        let operation_volume = operation.volumes[index].clone();
        let staging_exists = lv_exists(&operation_volume.staging_name)?;
        let active_exists = lv_exists(&volume.name)?;
        let rollback_exists = lv_exists(&operation_volume.rollback_name)?;

        if !staging_exists && active_exists {
            require_lv_tag(&volume.name, &format!("homelab-staging-{operation_id}"))?;
            if rollback_exists {
                run(
                    "lvchange",
                    &[
                        "--addtag",
                        &format!("homelab-rollback-{operation_id}"),
                        lv_path(&operation_volume.rollback_name)
                            .to_string_lossy()
                            .as_ref(),
                    ],
                )?;
            }
            run("lvchange", &["--activate", "y", &volume.lv])?;
            run("tune2fs", &["-U", &volume.uuid, &volume.lv])?;
            operation.volumes[index].had_active =
                operation.volumes[index].had_active || rollback_exists;
            operation.completed_volumes.push(volume.id.clone());
            operation.save()?;
            run(
                "lvchange",
                &[
                    "--deltag",
                    &format!("homelab-staging-{operation_id}"),
                    &volume.lv,
                ],
            )?;
            continue;
        }
        if !staging_exists {
            operation.phase = "cutover-failed".to_string();
            operation.save()?;
            return Err(format!(
                "missing staging LV {}",
                operation_volume.staging_name
            ));
        }
        require_lv_tag(
            &operation_volume.staging_name,
            &format!("homelab-staging-{operation_id}"),
        )?;
        ensure_unmounted(&volume.lv)?;
        operation.volumes[index].had_active = active_exists || rollback_exists;
        operation.save()?;

        if active_exists && !rollback_exists {
            let rollback = lv_path(&operation_volume.rollback_name);
            // The old filesystem must relinquish the stable UUID before the
            // restored filesystem receives it. This also prevents ambiguous
            // UUID-based activation while the rollback LV is retained.
            run(
                "lvchange",
                &[
                    "--addtag",
                    &format!("homelab-rollback-{operation_id}"),
                    &volume.lv,
                ],
            )?;
            run("tune2fs", &["-U", "random", &volume.lv])?;
            run(
                "lvrename",
                &[VG_NAME, &volume.name, &operation_volume.rollback_name],
            )?;
            run("udevadm", &["settle"])?;
            run(
                "lvchange",
                &["--activate", "n", rollback.to_string_lossy().as_ref()],
            )?;
        }
        if operation.volumes[index].had_active && rollback_exists {
            run(
                "lvchange",
                &[
                    "--addtag",
                    &format!("homelab-rollback-{operation_id}"),
                    lv_path(&operation_volume.rollback_name)
                        .to_string_lossy()
                        .as_ref(),
                ],
            )?;
        }

        run(
            "lvrename",
            &[VG_NAME, &operation_volume.staging_name, &volume.name],
        )?;
        run("udevadm", &["settle"])?;
        run("lvchange", &["--activate", "y", &volume.lv])?;
        run("tune2fs", &["-U", &volume.uuid, &volume.lv])?;
        operation.completed_volumes.push(volume.id.clone());
        operation.save()?;
        run(
            "lvchange",
            &[
                "--deltag",
                &format!("homelab-staging-{operation_id}"),
                &volume.lv,
            ],
        )?;
    }

    operation.phase = "cutover-complete".to_string();
    operation.save()?;
    println!(
        "restored LVs are active; enable and deploy service {:?}",
        operation.owner_service
    );
    Ok(())
}

pub fn run_restore_finalize(state_file: &Path, operation_id: &str) -> Result<(), String> {
    let state = load_state(state_file)?;
    let mut operation = load_operation(operation_id)?;
    if operation.phase != "cutover-complete" {
        return Err(format!(
            "operation {operation_id} is in phase {:?}, not ready to finalize",
            operation.phase
        ));
    }
    let volumes = operation_volumes(&state, &operation)?;
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let _locks = VolumeLocks::acquire(&ids, &format!("finalize:{operation_id}"))?;
    if volumes.iter().any(|volume| !volume.owner_enabled) {
        return Err(format!(
            "service {:?} is still disabled in the deployed configuration",
            operation.owner_service
        ));
    }
    if !service_is_active(&volumes[0].owner_unit)? {
        return Err(format!("{} is not active", volumes[0].owner_unit));
    }
    for volume in &volumes {
        verify_filesystem_identity(volume)?;
        let staging_tag = format!("homelab-staging-{operation_id}");
        if lv_has_tag(&volume.name, &staging_tag)? {
            run("lvchange", &["--deltag", &staging_tag, &volume.lv])?;
        }
    }
    operation.phase = "finalized".to_string();
    operation.save()?;
    println!("rollback LVs retained; operation {operation_id} finalized");
    Ok(())
}

pub fn run_restore_rollback(
    state_file: &Path,
    operation_id: &str,
    assume_yes: bool,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let mut operation = load_operation(operation_id)?;
    if !matches!(
        operation.phase.as_str(),
        "cutting-over" | "cutover-failed" | "cutover-complete" | "finalized" | "rolling-back"
    ) {
        return Err(format!(
            "operation {operation_id} has not cut over any volumes (phase {:?})",
            operation.phase
        ));
    }
    let volumes = operation_volumes(&state, &operation)?;
    require_staging_owner(&volumes)?;
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let _locks = VolumeLocks::acquire(&ids, &format!("rollback:{operation_id}"))?;
    let prompt = format!("roll back restore operation {operation_id}");
    if !assume_yes && !confirm(&prompt)? {
        return Err(format!("{prompt}: skipped"));
    }

    operation.phase = "rolling-back".to_string();
    operation.save()?;
    for index in (0..volumes.len()).rev() {
        let volume = &volumes[index];
        let operation_volume = &operation.volumes[index];
        if !operation.completed_volumes.contains(&volume.id) {
            continue;
        }
        ensure_unmounted(&volume.lv)?;
        let failed_exists = lv_exists(&operation_volume.failed_name)?;
        let active_exists = lv_exists(&volume.name)?;
        if active_exists && !failed_exists {
            run(
                "lvchange",
                &[
                    "--addtag",
                    &format!("homelab-failed-{operation_id}"),
                    &volume.lv,
                ],
            )?;
            run("tune2fs", &["-U", "random", &volume.lv])?;
            run(
                "lvrename",
                &[VG_NAME, &volume.name, &operation_volume.failed_name],
            )?;
            run(
                "lvchange",
                &[
                    "--activate",
                    "n",
                    lv_path(&operation_volume.failed_name)
                        .to_string_lossy()
                        .as_ref(),
                ],
            )?;
        }
        if operation_volume.had_active {
            if lv_exists(&operation_volume.rollback_name)? {
                run(
                    "lvrename",
                    &[VG_NAME, &operation_volume.rollback_name, &volume.name],
                )?;
                run("udevadm", &["settle"])?;
                run(
                    "lvchange",
                    &[
                        "--deltag",
                        &format!("homelab-rollback-{operation_id}"),
                        &volume.lv,
                    ],
                )?;
            }
            run("tune2fs", &["-U", &volume.uuid, &volume.lv])?;
            run("lvchange", &["--activate", "y", &volume.lv])?;
            verify_filesystem_identity(volume)?;
        }
        operation.completed_volumes.retain(|id| id != &volume.id);
        operation.save()?;
    }
    operation.phase = "rolled-back".to_string();
    operation.save()?;
    println!("restore operation {operation_id} rolled back; failed restored LVs were retained");
    Ok(())
}

pub fn run_restore_retire(
    state_file: &Path,
    operation_id: &str,
    assume_yes: bool,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let mut operation = load_operation(operation_id)?;
    if !matches!(operation.phase.as_str(), "finalized" | "rolled-back") {
        return Err(format!(
            "operation {operation_id} must be finalized or rolled back before retained LVs can be retired"
        ));
    }
    let volumes = operation_volumes(&state, &operation)?;
    let retiring_rollback = operation.phase == "finalized";
    if retiring_rollback && !service_is_active(&volumes[0].owner_unit)? {
        return Err(format!("{} is not active", volumes[0].owner_unit));
    }
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let _locks = VolumeLocks::acquire(&ids, &format!("retire:{operation_id}"))?;
    if retiring_rollback {
        for volume in &volumes {
            verify_filesystem_identity(volume)?;
        }
    }
    let retained_kind = if retiring_rollback {
        "rollback"
    } else {
        "failed restored"
    };
    let prompt = format!("permanently remove {retained_kind} LVs for operation {operation_id}");
    if !assume_yes && !confirm(&prompt)? {
        return Err(format!("{prompt}: skipped"));
    }
    for entry in &operation.volumes {
        let (name, expected_tag) = if retiring_rollback {
            if !entry.had_active {
                continue;
            }
            (
                &entry.rollback_name,
                format!("homelab-rollback-{operation_id}"),
            )
        } else {
            (&entry.failed_name, format!("homelab-failed-{operation_id}"))
        };
        if !lv_exists(name)? {
            continue;
        }
        remove_tagged_lv(name, &expected_tag)?;
    }
    operation.phase = if retiring_rollback {
        "retired".to_string()
    } else {
        "failed-retired".to_string()
    };
    operation.save()?;
    Ok(())
}

pub fn run_restore_abort(
    state_file: &Path,
    operation_id: &str,
    assume_yes: bool,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let mut operation = load_operation(operation_id)?;
    if !matches!(operation.kind.as_str(), "restore" | "migration")
        || !matches!(
            operation.phase.as_str(),
            "planned" | "restoring" | "failed" | "ready-for-cutover"
        )
    {
        return Err(format!(
            "operation {operation_id} cannot be aborted in phase {:?}",
            operation.phase
        ));
    }
    let volumes = operation_volumes(&state, &operation)?;
    require_staging_owner(&volumes)?;
    let ids = volumes
        .iter()
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    let _locks = VolumeLocks::acquire(&ids, &format!("abort:{operation_id}"))?;
    let prompt = format!("abandon operation {operation_id} and remove its staging LVs");
    if !assume_yes && !confirm(&prompt)? {
        return Err(format!("{prompt}: skipped"));
    }

    for (volume, entry) in volumes.iter().zip(&operation.volumes) {
        cleanup_restore_mount(operation_id, volume, entry)?;
        if lv_exists(&entry.staging_name)? {
            remove_tagged_lv(
                &entry.staging_name,
                &format!("homelab-staging-{operation_id}"),
            )?;
        }
    }
    let operation_root = Path::new(RESTORE_ROOT).join(operation_id);
    if operation_root.exists() {
        fs::remove_dir_all(&operation_root)
            .map_err(|error| format!("failed to remove {}: {error}", operation_root.display()))?;
    }
    operation.phase = "aborted".to_string();
    operation.save()?;
    Ok(())
}

pub fn run_restore_status(operation_id: &str) -> Result<(), String> {
    let operation = load_operation(operation_id)?;
    let value = serde_json::to_string_pretty(&operation)
        .map_err(|error| format!("failed to render operation: {error}"))?;
    println!("{value}");
    Ok(())
}

fn complete_service_backup(state: &State, owner_service: &str) -> Result<Vec<Volume>, String> {
    let volumes = backup_volumes(state, owner_service)?;
    let omitted = state
        .volumes
        .values()
        .filter(|volume| volume.owner_service == owner_service && volume.backup.is_none())
        .map(|volume| volume.id.clone())
        .collect::<Vec<_>>();
    if omitted.is_empty() {
        Ok(volumes)
    } else {
        Err(format!(
            "restore/migration requires every volume owned by {owner_service:?} in one Restic snapshot; missing backup policy: {}",
            omitted.join(", ")
        ))
    }
}

fn eligible_snapshots(
    target: &crate::models::BackupTarget,
    volumes: &[Volume],
    owner_service: &str,
    source_host: Option<&str>,
    required_tag: Option<&str>,
) -> Result<Vec<ResticSnapshot>, String> {
    let mut tags = vec![
        "homelab-volume".to_string(),
        format!("owner:{owner_service}"),
    ];
    for volume in volumes {
        tags.push(format!("volume:{}", volume.id));
        tags.push(format!("uuid:{}", volume.uuid));
    }
    if let Some(tag) = required_tag {
        tags.push(tag.to_string());
    }
    let mut snapshots = restic::snapshots(target, &tags, source_host)?;
    snapshots.sort_by(|left, right| right.time.cmp(&left.time));
    Ok(snapshots)
}

fn select_snapshot(
    snapshots: Vec<ResticSnapshot>,
    requested: Option<&str>,
) -> Result<ResticSnapshot, String> {
    if let Some(id) = requested {
        let matches = snapshots
            .into_iter()
            .filter(|snapshot| snapshot.id == id || snapshot.id.starts_with(id))
            .collect::<Vec<_>>();
        match matches.as_slice() {
            [] => Err(format!("snapshot {id:?} is not an eligible service backup")),
            [snapshot] => Ok(snapshot.clone()),
            _ => Err(format!("snapshot prefix {id:?} is ambiguous")),
        }
    } else {
        snapshots
            .into_iter()
            .next()
            .ok_or_else(|| "no eligible Restic snapshot found".to_string())
    }
}

fn require_staging_owner(volumes: &[Volume]) -> Result<(), String> {
    if volumes.iter().any(|volume| volume.owner_enabled) {
        return Err(format!(
            "service {:?} must be disabled in the deployed configuration before restore",
            volumes[0].owner_service
        ));
    }
    if service_is_active(&volumes[0].owner_unit)? {
        return Err(format!(
            "{} must be stopped before restore",
            volumes[0].owner_unit
        ));
    }
    Ok(())
}

fn prepare_staging_volume(
    volume: &Volume,
    operation: &OperationVolume,
    operation_id: &str,
) -> Result<(), String> {
    let path = staging_path(operation);
    if path.exists() {
        return Err(format!(
            "staging LV already exists: {}; inspect the operation before retrying",
            path.display()
        ));
    }
    run(
        "lvcreate",
        &[
            "--yes",
            "--size",
            &volume.size,
            "--addtag",
            &format!("homelab-staging-{operation_id}"),
            "--name",
            &operation.staging_name,
            VG_NAME,
        ],
    )?;
    run(
        &format!("mkfs.{}", volume.fs_type),
        &["-F", path.to_string_lossy().as_ref()],
    )
}

fn restore_one(
    target: &crate::models::BackupTarget,
    snapshot_id: &str,
    operation_id: &str,
    volume: &Volume,
    operation_volume: &OperationVolume,
) -> Result<(), String> {
    require_lv_tag(
        &operation_volume.staging_name,
        &format!("homelab-staging-{operation_id}"),
    )?;
    let operation_root = Path::new(RESTORE_ROOT).join(operation_id);
    let mount_path = restore_mount_path(operation_id, volume);
    cleanup_restore_mount(operation_id, volume, operation_volume)?;
    fs::create_dir_all(&mount_path)
        .map_err(|error| format!("failed to create {}: {error}", mount_path.display()))?;
    run(
        "mount",
        &[
            "--types",
            &volume.fs_type,
            staging_path(operation_volume).to_string_lossy().as_ref(),
            mount_path.to_string_lossy().as_ref(),
        ],
    )?;
    let result = (|| {
        let include = backup_mount_path(volume);
        let mut command = restic::command(target)?;
        command.args([
            "restore",
            snapshot_id,
            "--target",
            operation_root.to_string_lossy().as_ref(),
            "--include",
            include.to_string_lossy().as_ref(),
            "--verify",
        ]);
        restic::run(&mut command)
    })();
    let unmount = run("umount", &[mount_path.to_string_lossy().as_ref()]);
    result?;
    unmount?;
    run(
        "e2fsck",
        &[
            "-f",
            "-p",
            staging_path(operation_volume).to_string_lossy().as_ref(),
        ],
    )
}

fn cleanup_restore_mount(
    operation_id: &str,
    volume: &Volume,
    operation_volume: &OperationVolume,
) -> Result<(), String> {
    let mount_path = restore_mount_path(operation_id, volume);
    if !is_mountpoint(&mount_path)? {
        return Ok(());
    }
    let source = output(
        "findmnt",
        &[
            "--noheadings",
            "--output",
            "SOURCE",
            "--mountpoint",
            mount_path.to_string_lossy().as_ref(),
        ],
    )?;
    let actual = fs::canonicalize(source.trim()).map_err(|error| {
        format!(
            "failed to resolve mounted source {}: {error}",
            source.trim()
        )
    })?;
    let expected = fs::canonicalize(staging_path(operation_volume)).map_err(|error| {
        format!(
            "failed to resolve staging LV {}: {error}",
            staging_path(operation_volume).display()
        )
    })?;
    if actual != expected {
        return Err(format!(
            "refusing to unmount {}: expected source {}, got {}",
            mount_path.display(),
            expected.display(),
            actual.display()
        ));
    }
    run("umount", &[mount_path.to_string_lossy().as_ref()])
}

fn remove_tagged_lv(name: &str, expected_tag: &str) -> Result<(), String> {
    let path = lv_path(name);
    ensure_unmounted(path.to_string_lossy().as_ref())?;
    require_lv_tag(name, expected_tag)?;
    run("lvremove", &["--yes", path.to_string_lossy().as_ref()])
}

fn require_lv_tag(name: &str, expected_tag: &str) -> Result<(), String> {
    let path = lv_path(name);
    if !lv_has_tag(name, expected_tag)? {
        return Err(format!(
            "refusing to use {}: expected LVM tag {expected_tag:?} is missing",
            path.display()
        ));
    }
    Ok(())
}

fn lv_has_tag(name: &str, expected_tag: &str) -> Result<bool, String> {
    let tags = output(
        "lvs",
        &[
            "--noheadings",
            "--options",
            "lv_tags",
            lv_path(name).to_string_lossy().as_ref(),
        ],
    )?;
    Ok(tags.split(',').any(|tag| tag.trim() == expected_tag))
}

fn operation_volumes(state: &State, operation: &Operation) -> Result<Vec<Volume>, String> {
    operation
        .volumes
        .iter()
        .map(|entry| {
            let volume = state
                .volumes
                .get(&entry.id)
                .cloned()
                .ok_or_else(|| format!("volume {:?} is no longer declared", entry.id))?;
            if volume.name != entry.active_name
                || volume.uuid != entry.uuid
                || volume.fs_type != entry.fs_type
                || volume.owner_service != operation.owner_service
            {
                return Err(format!(
                    "volume {:?} declaration changed since operation {} was created",
                    entry.id, operation.id
                ));
            }
            Ok(volume)
        })
        .collect()
}

fn verify_filesystem_identity(volume: &Volume) -> Result<(), String> {
    let output = output("blkid", &["--probe", "--output", "export", &volume.lv])?;
    let fs_type = field(&output, "TYPE");
    let uuid = field(&output, "UUID");
    if fs_type.as_deref() != Some(&volume.fs_type) || uuid.as_deref() != Some(&volume.uuid) {
        return Err(format!(
            "[{}] restored filesystem identity mismatch: expected {}/{}, got {}/{}",
            volume.id,
            volume.fs_type,
            volume.uuid,
            fs_type.as_deref().unwrap_or("missing"),
            uuid.as_deref().unwrap_or("missing")
        ));
    }
    Ok(())
}

fn field(output: &str, name: &str) -> Option<String> {
    output
        .lines()
        .find_map(|line| line.strip_prefix(&format!("{name}=")))
        .map(str::to_string)
}

fn derived_lv_name(base: &str, kind: &str, operation_id: &str) -> String {
    let unique = operation_id
        .strip_prefix("restore-")
        .unwrap_or(operation_id);
    let suffix = format!("-{kind}-{unique}");
    let keep = 127usize.saturating_sub(suffix.len());
    format!("{}{}", &base[..base.len().min(keep)], suffix)
}

fn restore_mount_path(operation_id: &str, volume: &Volume) -> PathBuf {
    Path::new(RESTORE_ROOT).join(operation_id).join(
        backup_mount_path(volume)
            .strip_prefix("/")
            .unwrap_or_else(|_| {
                // backup_mount_path is constructed from an absolute constant.
                unreachable!("backup mount path must be absolute")
            }),
    )
}

fn staging_path(operation: &OperationVolume) -> PathBuf {
    lv_path(&operation.staging_name)
}

fn lv_path(name: &str) -> PathBuf {
    Path::new("/dev").join(VG_NAME).join(name)
}

fn lv_exists(name: &str) -> Result<bool, String> {
    let status = Command::new("lvs")
        .args(["--noheadings", &format!("{VG_NAME}/{name}")])
        .status()
        .map_err(|error| format!("failed to query LV {name}: {error}"))?;
    match status.code() {
        Some(0) => Ok(true),
        Some(5) => Ok(false),
        _ => Err(format!("lvs failed while querying {name}: {status}")),
    }
}

fn ensure_unmounted(device: &str) -> Result<(), String> {
    let status = Command::new("findmnt")
        .args(["--noheadings", "--source", device])
        .status()
        .map_err(|error| format!("failed to inspect mounts for {device}: {error}"))?;
    match status.code() {
        Some(1) => Ok(()),
        Some(0) => Err(format!("refusing to modify mounted filesystem {device}")),
        _ => Err(format!("findmnt failed for {device}: {status}")),
    }
}

fn is_mountpoint(path: &Path) -> Result<bool, String> {
    if !path.exists() {
        return Ok(false);
    }
    let status = Command::new("mountpoint")
        .args(["--quiet", path.to_string_lossy().as_ref()])
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

fn service_is_active(unit: &str) -> Result<bool, String> {
    let status = Command::new("systemctl")
        .args(["is-active", "--quiet", unit])
        .status()
        .map_err(|error| format!("failed to query {unit}: {error}"))?;
    match status.code() {
        Some(0) => Ok(true),
        Some(3 | 4) => Ok(false),
        _ => Err(format!("systemctl is-active {unit} failed with {status}")),
    }
}

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(program)
        .args(args)
        .status()
        .map_err(|error| format!("failed to execute {program}: {error}"))?;
    if status.success() || (program == "e2fsck" && matches!(status.code(), Some(0 | 1))) {
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

#[cfg(test)]
mod tests {
    use super::{derived_lv_name, select_snapshot};
    use crate::restic::ResticSnapshot;

    fn snapshot(id: &str) -> ResticSnapshot {
        ResticSnapshot {
            id: id.to_string(),
            time: "2026-09-13T00:00:00Z".to_string(),
            hostname: "host".to_string(),
            tags: Vec::new(),
        }
    }

    #[test]
    fn snapshot_prefix_must_be_unique() {
        let error = select_snapshot(
            vec![snapshot("abcdef01"), snapshot("abcdef02")],
            Some("abcdef"),
        )
        .unwrap_err();
        assert!(error.contains("ambiguous"));
    }

    #[test]
    fn derived_lv_names_fit_lvm_limit() {
        let name = derived_lv_name(&"a".repeat(127), "rollback", "restore-123-456-789");
        assert!(name.len() <= 127);
        assert!(name.ends_with("-rollback-123-456-789"));
    }
}
