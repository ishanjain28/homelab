use anyhow::{bail, ensure, Context, Result};
use std::{
    fs::{File, OpenOptions},
    io::{self, BufRead, BufReader, Read, Write},
    path::Path,
    process::{Command, Stdio},
};

use crate::{
    apply::{apply_volume, ensure_filesystem, grow_ext4_to_device, run_e2fsck, validate_volume},
    lock::VolumeLocks,
    lvm::{
        create_snapshot, derived_name, ensure_vg, has_tag, lv_exists, lv_field, lv_path,
        remove_snapshot, VG_NAME,
    },
    models::{load_state, service_volumes, Volume},
    quiesce::QuiesceGuard,
    util::{block_device_size, is_block_device, is_mounted, run_command},
};

const SNAPSHOT_TAG: &str = "homelab-copy";
const REMOTE_VOLUME: &str = "/run/current-system/sw/bin/volume";

pub fn run_copy(state_file: &Path, owner_service: &str, target: &str) -> Result<()> {
    validate_ssh_target(target)?;

    let state = load_state(state_file)?;
    let volumes = service_volumes(&state, owner_service)?;
    ensure!(
        volumes.iter().all(|volume| volume.owner_enabled),
        "source service {owner_service:?} must be enabled in the deployed configuration"
    );

    let _locks = VolumeLocks::acquire(&volumes, "copy")?;
    for volume in &volumes {
        validate_volume(volume).with_context(|| format!("[{}] validation failed", volume.id))?;
    }

    if let Err(error) = snapshot_and_copy(&volumes, owner_service, target) {
        cleanup_snapshots(&volumes)
            .with_context(|| format!("snapshot cleanup after failed copy: {error:#}"))?;
        return Err(error);
    }
    cleanup_snapshots(&volumes)
}

fn snapshot_and_copy(volumes: &[Volume], owner_service: &str, target: &str) -> Result<()> {
    let guard = QuiesceGuard::begin(&volumes[0].owner_unit)?;
    for volume in volumes {
        create_snapshot(
            volume,
            &snapshot_name(volume)?,
            SNAPSHOT_TAG,
            &volume.backup.snapshot_size,
        )
        .with_context(|| format!("[{}] snapshot failed", volume.id))?;
    }
    guard.release()?;
    for volume in volumes {
        copy_snapshot(volume, owner_service, target)
            .with_context(|| format!("[{}] copy failed", volume.id))?;
    }
    Ok(())
}

pub fn run_receive(
    state_file: &Path,
    owner_service: &str,
    volume_id: &str,
    source_bytes: u64,
) -> Result<()> {
    ensure!(
        source_bytes > 0,
        "source volume size must be greater than zero"
    );

    let state = load_state(state_file)?;
    let volume = state.volumes.get(volume_id).cloned().with_context(|| {
        format!(
            "volume {volume_id:?} is not declared on target host {}",
            state.host
        )
    })?;
    ensure!(
        volume.owner_service == owner_service,
        "target volume {volume_id:?} belongs to {:?}, not {owner_service:?}",
        volume.owner_service
    );
    ensure!(
        !volume.owner_enabled,
        "target service {owner_service:?} is enabled; disable it before receiving volume data"
    );

    let _locks = VolumeLocks::acquire(std::slice::from_ref(&volume), "receive")?;
    ensure_vg()?;

    if lv_exists(&volume.name)? {
        activate_lv(&volume.name)?;
        apply_volume(&volume, true)?;
        ensure!(
            block_device_size(&volume.lv)? >= source_bytes,
            "existing target LV {} is smaller than the source snapshot",
            volume.lv
        );
        send_handshake("SKIP")?;
        return Ok(());
    }

    let receiving_name = receiving_name(&volume)?;
    remove_receiving_lv(&volume, &receiving_name)?;
    run_command(
        "lvcreate",
        &[
            "--yes",
            "--size",
            &volume.size,
            "--name",
            &receiving_name,
            "--addtag",
            "homelab-receiving",
            "--addtag",
            &format!("homelab-volume-{}", volume.id),
            VG_NAME,
        ],
    )?;
    run_command("udevadm", &["settle"])?;

    let receiving_path = lv_path(&receiving_name);
    let receiving_bytes = block_device_size(&receiving_path)?;
    if receiving_bytes < source_bytes {
        remove_receiving_lv(&volume, &receiving_name)?;
        bail!(
            "target declaration for {volume_id:?} creates a {receiving_bytes}-byte LV, smaller than the {source_bytes}-byte source LV"
        );
    }

    send_handshake("READY")?;
    let mut device = OpenOptions::new()
        .write(true)
        .open(&receiving_path)
        .with_context(|| format!("failed to open {}", receiving_path.display()))?;
    let copied = io::copy(&mut io::stdin().lock().take(source_bytes), &mut device)
        .with_context(|| format!("failed writing {}", receiving_path.display()))?;
    ensure!(
        copied == source_bytes,
        "incomplete transfer for {volume_id:?}: received {copied} of {source_bytes} bytes"
    );
    device
        .sync_all()
        .with_context(|| format!("failed to flush {}", receiving_path.display()))?;
    drop(device);

    let mut received = volume.clone();
    received.name = receiving_name.clone();
    received.lv = receiving_path.to_string_lossy().into_owned();
    run_e2fsck(&received)?;
    ensure_filesystem(&received)?;
    if receiving_bytes > source_bytes {
        grow_ext4_to_device(&received)?;
        ensure_filesystem(&received)?;
    }

    run_command("lvrename", &[VG_NAME, &receiving_name, &volume.name])?;
    run_command("udevadm", &["settle"])?;
    ensure_filesystem(&volume)
}

fn copy_snapshot(volume: &Volume, owner_service: &str, target: &str) -> Result<()> {
    let snapshot = lv_path(&snapshot_name(volume)?);
    let source_bytes = block_device_size(&snapshot)?;
    log::info!(volume = volume.id; "copying {source_bytes} bytes to {target}");

    let mut child = Command::new("ssh")
        .arg(target)
        .args([
            REMOTE_VOLUME,
            "receive",
            owner_service,
            &volume.id,
            "--source-bytes",
            &source_bytes.to_string(),
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to start receiver on {target}"))?;

    let stdout = child.stdout.take().context("receiver has no stdout")?;
    let mut handshake = String::new();
    BufReader::new(stdout)
        .read_line(&mut handshake)
        .context("failed to read receiver handshake")?;

    let transfer = match handshake.trim() {
        "READY" => stream_snapshot(&snapshot, source_bytes, &mut child),
        "SKIP" => {
            drop(child.stdin.take());
            log::info!(volume = volume.id; "target already contains this volume");
            Ok(())
        }
        response => {
            drop(child.stdin.take());
            Err(anyhow::anyhow!("unexpected receiver response {response:?}"))
        }
    };

    let status = child
        .wait()
        .with_context(|| format!("failed to wait for receiver on {target}"))?;
    ensure!(
        status.success(),
        "receiver on {target} failed with {status}"
    );
    transfer
}

fn stream_snapshot(
    snapshot: &Path,
    source_bytes: u64,
    child: &mut std::process::Child,
) -> Result<()> {
    let mut input =
        File::open(snapshot).with_context(|| format!("failed to open {}", snapshot.display()))?;
    let mut remote_input = child.stdin.take().context("receiver has no stdin")?;
    let copied = io::copy(&mut input, &mut remote_input)
        .with_context(|| format!("failed to stream {}", snapshot.display()))?;
    drop(remote_input);
    ensure!(
        copied == source_bytes,
        "short read from {}: copied {copied} of {source_bytes} bytes",
        snapshot.display()
    );
    Ok(())
}

fn cleanup_snapshots(volumes: &[Volume]) -> Result<()> {
    for volume in volumes.iter().rev() {
        remove_snapshot(volume, &snapshot_name(volume)?, SNAPSHOT_TAG)?;
    }
    Ok(())
}

fn remove_receiving_lv(volume: &Volume, name: &str) -> Result<()> {
    if !lv_exists(name)? {
        return Ok(());
    }
    let path = lv_path(name);
    let tags = lv_field(name, "lv_tags")?;
    ensure!(
        has_tag(&tags, "homelab-receiving")
            && has_tag(&tags, &format!("homelab-volume-{}", volume.id)),
        "refusing to remove existing LV {name:?}: expected homelab receiving tags"
    );
    ensure!(
        !is_mounted(path.to_string_lossy().as_ref())?,
        "refusing to remove mounted LV {}",
        path.display()
    );
    run_command("lvremove", &["--yes", &path.to_string_lossy()])
}

fn activate_lv(name: &str) -> Result<()> {
    let path = lv_path(name);
    if !is_block_device(&path) {
        run_command("lvchange", &["--activate", "y", &path.to_string_lossy()])?;
        run_command("udevadm", &["settle"])?;
    }
    Ok(())
}

fn send_handshake(value: &str) -> Result<()> {
    let mut stdout = io::stdout().lock();
    writeln!(stdout, "{value}")
        .and_then(|()| stdout.flush())
        .context("failed to write handshake")
}

fn snapshot_name(volume: &Volume) -> Result<String> {
    derived_name(&volume.name, "-copy")
}

fn receiving_name(volume: &Volume) -> Result<String> {
    derived_name(&volume.name, "-receiving")
}

fn validate_ssh_target(target: &str) -> Result<()> {
    let valid = !target.is_empty()
        && !target.starts_with('-')
        && target.chars().all(|character| {
            character.is_ascii_alphanumeric()
                || matches!(character, '.' | '-' | '_' | ':' | '@' | '[' | ']' | '%')
        });
    ensure!(valid, "invalid SSH target {target:?}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::validate_ssh_target;

    #[test]
    fn validates_ssh_targets() {
        assert!(validate_ssh_target("copernicus").is_ok());
        assert!(validate_ssh_target("root@10.0.99.8").is_ok());
        assert!(validate_ssh_target("-oProxyCommand=bad").is_err());
        assert!(validate_ssh_target("host;bad").is_err());
    }
}
