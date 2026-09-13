use crate::lock::VolumeLocks;
use crate::lvm::{lv_exists, lv_path};
use crate::models::{load_state, Volume};
use crate::util::{confirm, is_mounted, run_command};
use std::path::Path;
use std::process::Command;

pub fn run_retire(state_file: &Path, volume_id: &str, assume_yes: bool) -> Result<(), String> {
    let state = load_state(state_file)?;
    let tombstone = state.deleted_volumes.get(volume_id).ok_or_else(|| {
        format!(
            "volume {volume_id:?} has no deployed deletedVolumes tombstone; retirement is refused"
        )
    })?;
    if state.volumes.contains_key(volume_id) {
        return Err(format!("volume {volume_id:?} is still actively declared"));
    }
    let today = output("date", &["+%F"])?.trim().to_string();
    if tombstone.after > today {
        return Err(format!(
            "volume {volume_id:?} cannot be retired before {} (today is {today})",
            tombstone.after
        ));
    }
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
    };
    let _locks = VolumeLocks::acquire(std::slice::from_ref(&lock_volume), "retire")?;
    let lv = lv_path(&tombstone.name);
    if !lv_exists(&tombstone.name)? {
        return Err(format!("retired LV does not exist: {}", lv.display()));
    }
    if is_mounted(lv.to_string_lossy().as_ref())? {
        return Err(format!("refusing to remove mounted LV {}", lv.display()));
    }
    if !lv.exists() {
        run_command(
            "lvchange",
            &["--activate", "y", lv.to_string_lossy().as_ref()],
        )?;
    }
    let snapshots = output(
        "lvs",
        &[
            "--noheadings",
            "--options",
            "lv_name",
            "--select",
            &format!("origin={}", tombstone.name),
        ],
    )?;
    if !snapshots.trim().is_empty() {
        return Err(format!(
            "refusing to remove {} while snapshots exist: {}",
            lv.display(),
            snapshots.trim()
        ));
    }
    let identity = output(
        "blkid",
        &[
            "--probe",
            "--output",
            "export",
            lv.to_string_lossy().as_ref(),
        ],
    )?;
    let actual_uuid = identity.lines().find_map(|line| line.strip_prefix("UUID="));
    if actual_uuid != Some(tombstone.uuid.as_str()) {
        return Err(format!(
            "refusing to remove {}: expected filesystem UUID {}, got {}",
            lv.display(),
            tombstone.uuid,
            actual_uuid.unwrap_or("missing")
        ));
    }
    let prompt = format!(
        "permanently remove {} for retired volume {volume_id:?} ({})",
        lv.display(),
        tombstone.reason
    );
    if !confirm(assume_yes, &prompt)? {
        return Err(format!("{prompt}: skipped"));
    }
    run_command("lvremove", &["--yes", lv.to_string_lossy().as_ref()])
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
