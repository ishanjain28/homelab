use std::{
    fs,
    os::fd::AsRawFd,
    path::{Path, PathBuf},
    time::Duration,
};

use crate::{
    lock::VolumeLocks,
    lvm::{create_snapshot, derived_name, ensure_vg, lv_path, remove_snapshot},
    models::{backup_volumes, load_state, Volume},
    quiesce::{thaw_if_frozen, QuiesceGuard},
    util::{is_block_device, is_mountpoint, run_command},
};

const BACKUP_ROOT: &str = "/run/homelab-backup";
const SNAPSHOT_TAG: &str = "homelab-backup";
const MOUNT_OPTIONS: &str = "ro,noload,nodev,nosuid,noexec";

/// Snapshot every volume that `owner_service` contributes to `group` inside
/// one freeze window, then mount the snapshots read-only under
/// `/run/homelab-backup/<group>/<volume-id>` for the backup job to read.
pub fn run_backup_prepare(
    state_file: &Path,
    group: &str,
    owner_service: &str,
    wait: Duration,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let volumes = backup_volumes(&state, group, owner_service)?;
    let _locks = VolumeLocks::acquire_ids(
        &lock_ids(&volumes, owner_service),
        &format!("backup-prepare:{group}"),
        wait,
    )?;
    ensure_vg()?;
    for volume in &volumes {
        if !is_block_device(Path::new(&volume.lv)) {
            return Err(format!("[{}] missing LV {}", volume.id, volume.lv));
        }
    }

    let unit = &volumes[0].owner_unit;

    // Leftovers from an interrupted run: thaw the owner and drop stale
    // snapshots before taking new ones.
    thaw_if_frozen(unit)?;
    release_volumes(group, &volumes)?;

    if let Err(error) = snapshot_and_mount(group, unit, &volumes) {
        if let Err(cleanup_error) = release_volumes(group, &volumes) {
            return Err(format!("{error}\ncleanup also failed: {cleanup_error}"));
        }
        return Err(error);
    }
    Ok(())
}

/// Unmount and remove the snapshots created by `run_backup_prepare` and thaw
/// the owner if an interrupted run left it frozen.
pub fn run_backup_cleanup(
    state_file: &Path,
    group: &str,
    owner_service: &str,
    wait: Duration,
) -> Result<(), String> {
    let state = load_state(state_file)?;
    let volumes = backup_volumes(&state, group, owner_service)?;
    let _locks = VolumeLocks::acquire_ids(
        &lock_ids(&volumes, owner_service),
        &format!("backup-cleanup:{group}"),
        wait,
    )?;

    let released = release_volumes(group, &volumes);
    thaw_if_frozen(&volumes[0].owner_unit)?;
    released?;
    let _ = fs::remove_dir(group_dir(group));
    Ok(())
}

fn snapshot_and_mount(group: &str, unit: &str, volumes: &[Volume]) -> Result<(), String> {
    let guard = QuiesceGuard::begin(unit)?;
    for volume in volumes {
        syncfs(&volume.host_mount_path)?;
    }
    for volume in volumes {
        log::info!(volume = volume.id; "creating snapshot");
        create_snapshot(
            volume,
            &snapshot_name(volume, group)?,
            SNAPSHOT_TAG,
            &volume.backup.snapshot_size,
        )?;
    }
    guard.release()?;

    for volume in volumes {
        mount_snapshot(group, volume)?;
    }
    Ok(())
}

fn lock_ids(volumes: &[Volume], owner_service: &str) -> Vec<String> {
    let mut ids = Vec::with_capacity(volumes.len() + 1);
    for volume in volumes {
        ids.push(volume.id.clone());
    }
    ids.push(format!("owner@{owner_service}"));
    ids
}

fn release_volumes(group: &str, volumes: &[Volume]) -> Result<(), String> {
    for volume in volumes {
        let dir = mount_dir(group, &volume.id);
        if is_mountpoint(&dir)? {
            run_command("umount", &[&dir.to_string_lossy()])?;
        }
        remove_snapshot(volume, &snapshot_name(volume, group)?, SNAPSHOT_TAG)?;
        let _ = fs::remove_dir(&dir);
    }
    Ok(())
}

fn mount_snapshot(group: &str, volume: &Volume) -> Result<(), String> {
    let dir = mount_dir(group, &volume.id);
    fs::create_dir_all(&dir)
        .map_err(|error| format!("failed to create {}: {error}", dir.display()))?;
    let snapshot = lv_path(&snapshot_name(volume, group)?);
    run_command(
        "mount",
        &[
            "--types",
            &volume.fs_type,
            "--options",
            MOUNT_OPTIONS,
            &snapshot.to_string_lossy(),
            &dir.to_string_lossy(),
        ],
    )
}

fn syncfs(path: &str) -> Result<(), String> {
    let file = fs::File::open(path).map_err(|error| format!("failed to open {path}: {error}"))?;
    if unsafe { libc::syncfs(file.as_raw_fd()) } != 0 {
        return Err(format!(
            "syncfs failed for {path}: {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

fn snapshot_name(volume: &Volume, group: &str) -> Result<String, String> {
    derived_name(&volume.name, &format!("-bk-{group}"))
}

fn group_dir(group: &str) -> PathBuf {
    Path::new(BACKUP_ROOT).join(group)
}

fn mount_dir(group: &str, volume_id: &str) -> PathBuf {
    group_dir(group).join(volume_id)
}
