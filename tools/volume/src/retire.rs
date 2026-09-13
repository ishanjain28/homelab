use crate::lock::VolumeLocks;
use crate::models::load_state;
use crate::prompt::confirm;
use std::path::{Path, PathBuf};
use std::process::Command;

const VG_NAME: &str = "pool";

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
    let _locks = VolumeLocks::acquire(&[volume_id.to_string()], "retire")?;
    let lv = lv_path(&tombstone.name);
    if !lv_exists(&tombstone.name)? {
        return Err(format!("retired LV does not exist: {}", lv.display()));
    }
    if is_mounted(&lv)? {
        return Err(format!("refusing to remove mounted LV {}", lv.display()));
    }
    if !lv.exists() {
        run(
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
    if !assume_yes && !confirm(&prompt)? {
        return Err(format!("{prompt}: skipped"));
    }
    run("lvremove", &["--yes", lv.to_string_lossy().as_ref()])
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

fn is_mounted(device: &Path) -> Result<bool, String> {
    let status = Command::new("findmnt")
        .args([
            "--noheadings",
            "--source",
            device.to_string_lossy().as_ref(),
        ])
        .status()
        .map_err(|error| format!("failed to query mounts for {}: {error}", device.display()))?;
    match status.code() {
        Some(0) => Ok(true),
        Some(1) => Ok(false),
        _ => Err(format!("findmnt failed for {}: {status}", device.display())),
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
