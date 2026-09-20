use anyhow::{ensure, Context, Result};
use std::path::Path;

use crate::{
    lock::VolumeLocks,
    lvm::{lv_exists, lv_path},
    models::{load_state, BackupPolicy, Volume},
    util::{command_stdout, confirm, is_mounted, run_command},
};

pub fn run_retire(state_file: &Path, volume_id: &str, assume_yes: bool) -> Result<()> {
    let state = load_state(state_file)?;
    let tombstone = state.deleted_volumes.get(volume_id).with_context(|| {
        format!(
            "volume {volume_id:?} has no deployed deletedVolumes tombstone; retirement is refused"
        )
    })?;
    ensure!(
        !state.volumes.contains_key(volume_id),
        "volume {volume_id:?} is still actively declared"
    );
    let today = command_stdout("date", &["+%F"])?;
    ensure!(
        tombstone.after <= today,
        "volume {volume_id:?} cannot be retired before {} (today is {today})",
        tombstone.after
    );
    let lock_volume = Volume {
        id: volume_id.to_string(),
        lv: String::new(),
        name: tombstone.name.clone(),
        size: String::new(),
        fs_type: String::new(),
        uuid: tombstone.uuid.clone(),
        owner_service: String::new(),
        owner_enabled: false,
        owner_unit: String::new(),
        host_mount_path: String::new(),
        mount_path: String::new(),
        mode: String::new(),
        backup: BackupPolicy::default(),
    };
    let _locks = VolumeLocks::acquire(std::slice::from_ref(&lock_volume), "retire")?;
    let lv = lv_path(&tombstone.name);
    let lv_str = lv.to_string_lossy();
    ensure!(
        lv_exists(&tombstone.name)?,
        "retired LV does not exist: {}",
        lv.display()
    );
    ensure!(
        !is_mounted(&lv_str)?,
        "refusing to remove mounted LV {}",
        lv.display()
    );
    if !lv.exists() {
        run_command("lvchange", &["--activate", "y", &lv_str])?;
    }
    let snapshots = command_stdout(
        "lvs",
        &[
            "--noheadings",
            "--options",
            "lv_name",
            "--select",
            &format!("origin={}", tombstone.name),
        ],
    )?;
    ensure!(
        snapshots.is_empty(),
        "refusing to remove {} while snapshots exist: {snapshots}",
        lv.display()
    );
    let identity = command_stdout("blkid", &["--probe", "--output", "export", &lv_str])?;
    let actual_uuid = identity
        .lines()
        .find_map(|line| line.strip_prefix("UUID="))
        .unwrap_or("missing");
    ensure!(
        actual_uuid == tombstone.uuid,
        "refusing to remove {}: expected filesystem UUID {}, got {actual_uuid}",
        lv.display(),
        tombstone.uuid
    );
    let prompt = format!(
        "permanently remove {} for retired volume {volume_id:?} ({})",
        lv.display(),
        tombstone.reason
    );
    ensure!(confirm(assume_yes, &prompt)?, "{prompt}: skipped");
    run_command("lvremove", &["--yes", &lv_str])
}
