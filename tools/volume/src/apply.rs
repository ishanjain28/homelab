use anyhow::{bail, ensure, Context, Result};
use std::{path::Path, process::Command};

use crate::{
    lock::VolumeLocks,
    lvm::{ensure_vg, lv_name, VG_NAME},
    models::{load_all_volumes, load_volumes, Volume},
    util::{
        block_device_size, command_output, confirm, is_block_device, is_mounted,
        parse_blkid_output, parse_size, run_command,
    },
};

pub fn run_apply(state_file: &Path, assume_yes: bool, volume_ids: Vec<String>) -> Result<()> {
    let mut volumes = load_volumes(state_file, &volume_ids)?;
    if volumes.is_empty() {
        // Check all volumes if none is specified
        volumes = load_all_volumes(state_file)?;
    }

    let _locks = VolumeLocks::acquire(&volumes, "apply")?;

    log::info!("{}", serde_json::to_string_pretty(&volumes)?);

    for volume in volumes {
        log::info!(volume = volume.id; "apply");
        apply_volume(&volume, assume_yes)
            .with_context(|| format!("[{}] apply failed", volume.id))?;
        log::info!(volume = volume.id; "applied");
    }

    Ok(())
}

pub(crate) fn apply_volume(volume: &Volume, assume_yes: bool) -> Result<()> {
    let expected_size = parse_size(&volume.size)?;

    ensure_vg()?;
    if !is_block_device(Path::new(&volume.lv)) {
        return create_volume(volume, assume_yes);
    }
    ensure_filesystem(volume)?;
    ensure_size(volume, expected_size, assume_yes)?;

    Ok(())
}

pub(crate) fn validate_volume(volume: &Volume) -> Result<()> {
    ensure_vg()?;
    ensure!(
        is_block_device(Path::new(&volume.lv)),
        "missing source LV {}",
        volume.lv
    );
    ensure_filesystem(volume)?;

    let actual_size = block_device_size(&volume.lv)?;
    let expected_size = parse_size(&volume.size)?;
    ensure!(
        actual_size == expected_size,
        "LV size does not match its declaration: actual {actual_size} bytes, declared {expected_size} bytes ({})",
        volume.size
    );

    Ok(())
}

fn create_volume(volume: &Volume, assume_yes: bool) -> Result<()> {
    let prompt = format!(
        "[{}] create and format {} ({}, {})",
        volume.id, volume.lv, volume.size, volume.fs_type
    );
    ensure!(confirm(assume_yes, &prompt)?, "{prompt}: skipped");

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

    run_command(
        &format!("mkfs.{}", volume.fs_type),
        &["-F", "-U", &volume.uuid, &volume.lv],
    )
    .with_context(|| {
        format!(
            "filesystem creation failed; the unformatted LV has been retained at {}",
            volume.lv
        )
    })?;

    ensure_filesystem(volume)
}

pub(crate) fn ensure_filesystem(volume: &Volume) -> Result<()> {
    let (actual_type, actual_uuid) = probe_filesystem(volume)?;

    ensure!(
        actual_type == volume.fs_type,
        "filesystem type mismatch on {}: expected {}, got {actual_type}",
        volume.lv,
        volume.fs_type
    );
    ensure!(
        actual_uuid == volume.uuid,
        "UUID mismatch on {}: expected {}, got {actual_uuid}",
        volume.lv,
        volume.uuid
    );

    Ok(())
}

fn probe_filesystem(volume: &Volume) -> Result<(String, String)> {
    let output = Command::new("blkid")
        .args(["--probe", "--output", "export", &volume.lv])
        .output()
        .context("failed to run blkid")?;
    let fields = parse_blkid_output(output)
        .with_context(|| format!("failed to probe filesystem on {}", volume.lv))?;

    let field = |name: &str| {
        fields
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.clone())
    };
    match (field("TYPE"), field("UUID")) {
        (Some(fs_type), Some(uuid)) => Ok((fs_type, uuid)),
        _ => bail!(
            "filesystem on {} does not expose both TYPE and UUID",
            volume.lv
        ),
    }
}

fn ensure_size(volume: &Volume, expected_size: u64, assume_yes: bool) -> Result<()> {
    let actual_size = block_device_size(&volume.lv)?;

    if actual_size < expected_size {
        ensure!(
            !is_mounted(&volume.lv)?,
            "refusing to grow mounted volume {}; stop its service and unmount it first",
            volume.lv
        );
        let prompt = format!(
            "[{}] grow {} from {} bytes to {}",
            volume.id, volume.lv, actual_size, volume.size
        );
        ensure!(confirm(assume_yes, &prompt)?, "{prompt}: skipped");
        run_command("lvextend", &["--yes", "--size", &volume.size, &volume.lv])?;

        grow_ext4_to_device(volume)?;
    } else if actual_size > expected_size {
        bail!(
            "refusing size decrease for {}: current size is {actual_size} bytes, declared size is {expected_size} bytes ({})",
            volume.lv,
            volume.size
        );
    }

    Ok(())
}

pub(crate) fn grow_ext4_to_device(volume: &Volume) -> Result<()> {
    let Err(error) = run_command("resize2fs", &[&volume.lv]) else {
        return Ok(());
    };
    if !format!("{error:#}").contains("e2fsck -f") {
        return Err(error);
    }

    log::warn!(volume = volume.id; "filesystem requires a check before resize; running e2fsck");
    run_e2fsck(volume)?;
    run_command("resize2fs", &[&volume.lv])
}

pub(crate) fn run_e2fsck(volume: &Volume) -> Result<()> {
    let output = Command::new("e2fsck")
        .args(["-f", "-p", &volume.lv])
        .output()
        .context("failed to run e2fsck")?;

    match output.status.code() {
        Some(0 | 1) => Ok(()),
        status => bail!(
            "e2fsck failed for {} (status {}): {}",
            volume.lv,
            status.map_or_else(|| "signal".to_string(), |code| code.to_string()),
            command_output(&output)
        ),
    }
}
