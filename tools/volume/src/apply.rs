use crate::{
    lock::VolumeLocks,
    lvm::{ensure_vg, lv_name, VG_NAME},
    models::{load_all_volumes, load_volumes, Volume},
    util::confirm,
    util::{
        block_device_size, command_output, is_block_device, is_mounted, parse_blkid_output,
        parse_size, run_command,
    },
};
use std::{path::Path, process::Command};

pub fn run_apply(
    state_file: &Path,
    assume_yes: bool,
    volume_ids: Vec<String>,
) -> Result<(), String> {
    let mut volumes = load_volumes(state_file, &volume_ids)?;
    if volumes.is_empty() {
        // Check all volumes if none is specified
        volumes = load_all_volumes(state_file)?;
    }

    let _locks = VolumeLocks::acquire(&volumes, "apply")?;

    log::info!("{}", serde_json::to_string_pretty(&volumes).unwrap());

    for volume in volumes {
        log::info!(volume = volume.id; "apply");
        apply_volume(&volume, assume_yes)?;
        log::info!(volume = volume.id; "applied");
    }

    Ok(())
}

pub(crate) fn apply_volume(volume: &Volume, assume_yes: bool) -> Result<(), String> {
    let expected_size = parse_size(&volume.size)?;

    ensure_vg()?;
    if !is_block_device(Path::new(&volume.lv)) {
        return create_volume(volume, assume_yes);
    }
    ensure_filesystem(volume)?;
    ensure_size(volume, expected_size, assume_yes)?;

    Ok(())
}

pub(crate) fn validate_volume(volume: &Volume) -> Result<(), String> {
    ensure_vg()?;
    if !is_block_device(Path::new(&volume.lv)) {
        return Err(format!("missing source LV {}", volume.lv));
    }
    ensure_filesystem(volume)?;

    let actual_size = block_device_size(&volume.lv)?;
    let expected_size = parse_size(&volume.size)?;
    if actual_size != expected_size {
        return Err(format!(
            "[{}] source LV size does not match its declaration: actual {actual_size} bytes, declared {expected_size} bytes ({})",
            volume.id, volume.size
        ));
    }

    Ok(())
}

fn create_volume(volume: &Volume, assume_yes: bool) -> Result<(), String> {
    let prompt = format!(
        "[{}] create and format {} ({}, {})",
        volume.id, volume.lv, volume.size, volume.fs_type
    );
    if !confirm(assume_yes, &prompt)? {
        return Err(format!("{prompt}: skipped"));
    }

    run_command(
        "lvcreate",
        &[
            "--yes",
            "--size",
            &volume.size,
            "--name",
            &lv_name(&volume.lv)?,
            VG_NAME,
        ],
    )?;

    if let Err(error) = run_command(
        &format!("mkfs.{}", volume.fs_type),
        &["-F", "-U", &volume.uuid, &volume.lv],
    ) {
        return Err(format!(
            "filesystem creation failed; the unformatted LV has been retained at {}: {error}",
            volume.lv
        ));
    }

    ensure_filesystem(volume)?;
    Ok(())
}

pub(crate) fn ensure_filesystem(volume: &Volume) -> Result<(), String> {
    let (actual_type, actual_uuid) = probe_filesystem(volume)?;

    if actual_type != volume.fs_type {
        return Err(format!(
            "filesystem type mismatch: expected {}, got {}",
            volume.fs_type, actual_type
        ));
    }
    if actual_uuid != volume.uuid {
        return Err(format!(
            "UUID mismatch: expected {}, got {}",
            volume.uuid, actual_uuid
        ));
    }

    Ok(())
}

fn probe_filesystem(volume: &Volume) -> Result<(String, String), String> {
    let output = Command::new("blkid")
        .args(["--probe", "--output", "export", &volume.lv])
        .output()
        .map_err(|error| format!("failed to run blkid: {error}"))?;

    let blkid_output = parse_blkid_output(output);

    match blkid_output {
        Ok(v) => {
            match (
                v.iter().find(|(x, _)| x == "TYPE"),
                v.iter().find(|(x, _)| x == "UUID"),
            ) {
                (Some((_, t)), Some((_, u))) => Ok((t.to_owned(), u.to_owned())),

                _ => Err(format!(
                    "filesystem on {} does not expose both TYPE and UUID",
                    volume.lv
                )),
            }
        }

        Err(error) => Err(format!(
            "failed to probe filesystem on {} msg: {error}",
            volume.lv
        )),
    }
}

fn ensure_size(volume: &Volume, expected_size: u64, assume_yes: bool) -> Result<(), String> {
    let actual_size = block_device_size(&volume.lv)?;

    if actual_size < expected_size {
        if is_mounted(&volume.lv)? {
            return Err(format!(
                "refusing to grow mounted volume {}; stop its service and unmount it first",
                volume.lv
            ));
        }
        let prompt = format!(
            "[{}] grow {} from {} bytes to {}",
            volume.id, volume.lv, actual_size, volume.size
        );
        if !confirm(assume_yes, &prompt)? {
            return Err(format!("{prompt}: skipped"));
        }
        run_command("lvextend", &["--yes", "--size", &volume.size, &volume.lv])?;

        grow_ext4_to_device(volume)?;
    } else if actual_size > expected_size {
        return Err(format!(
            "[{}] refusing size decrease for {}: current size is {actual_size} bytes, declared size is {expected_size} bytes ({})",
            volume.id, volume.lv, volume.size
        ));
    }

    Ok(())
}

pub(crate) fn grow_ext4_to_device(volume: &Volume) -> Result<(), String> {
    let error = match run_command("resize2fs", &[&volume.lv]) {
        Ok(()) => return Ok(()),
        Err(error) => error,
    };

    if !error.contains("e2fsck -f") {
        return Err(error);
    }

    log::warn!(volume = volume.id; "filesystem requires a check before resize; running e2fsck");
    run_e2fsck(volume)?;
    run_command("resize2fs", &[&volume.lv])
}

pub(crate) fn run_e2fsck(volume: &Volume) -> Result<(), String> {
    let output = Command::new("e2fsck")
        .args(["-f", "-p", &volume.lv])
        .output()
        .map_err(|error| format!("failed to run e2fsck: {error}"))?;

    match output.status.code() {
        Some(0 | 1) => Ok(()),
        status => Err(format!(
            "e2fsck failed for {} (status {}): {}",
            volume.lv,
            status.map_or_else(|| "signal".to_string(), |code| code.to_string()),
            command_output(&output)
        )),
    }
}
