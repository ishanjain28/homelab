use std::{
    fs::{File, OpenOptions},
    io::{self, BufRead, BufReader, Read, Write},
    path::Path,
    process::{Command, Stdio},
};

use crate::{
    apply::{apply_volume, ensure_filesystem, grow_ext4_to_device, run_e2fsck, validate_volume},
    lock::VolumeLocks,
    lvm::{ensure_vg, lv_exists, lv_field, lv_path, VG_NAME},
    models::{load_state, service_volumes, Volume},
    util::{block_device_size, is_block_device, is_mounted, run_command},
};

const SNAPSHOT_EXTENTS: &str = "20%ORIGIN";
const REMOTE_VOLUME: &str = "/run/current-system/sw/bin/volume";

pub fn run_copy(state_file: &Path, owner_service: &str, target: &str) -> Result<(), String> {
    validate_ssh_target(target)?;

    let state = load_state(state_file)?;
    let volumes = service_volumes(&state, owner_service)?;
    if volumes.iter().any(|volume| !volume.owner_enabled) {
        return Err(format!(
            "source service {owner_service:?} must be enabled in the deployed configuration"
        ));
    }

    let _locks = VolumeLocks::acquire(&volumes, "copy")?;
    for volume in &volumes {
        validate_volume(volume)?;
    }

    let result = (|| {
        for volume in &volumes {
            create_snapshot(volume)?;
        }
        for volume in &volumes {
            copy_snapshot(volume, owner_service, target)?;
        }
        Ok(())
    })();
    let cleanup = cleanup_snapshots(&volumes);

    match (result, cleanup) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) => Err(error),
        (Ok(()), Err(error)) => Err(error),
        (Err(error), Err(cleanup_error)) => Err(format!(
            "{error}\nsnapshot cleanup also failed: {cleanup_error}"
        )),
    }
}

pub fn run_receive(
    state_file: &Path,
    owner_service: &str,
    volume_id: &str,
    source_bytes: u64,
) -> Result<(), String> {
    if source_bytes == 0 {
        return Err("source volume size must be greater than zero".to_string());
    }

    let state = load_state(state_file)?;
    let volume = state.volumes.get(volume_id).cloned().ok_or_else(|| {
        format!(
            "volume {volume_id:?} is not declared on target host {}",
            state.host
        )
    })?;
    if volume.owner_service != owner_service {
        return Err(format!(
            "target volume {volume_id:?} belongs to {:?}, not {owner_service:?}",
            volume.owner_service
        ));
    }
    if volume.owner_enabled {
        return Err(format!(
            "target service {owner_service:?} is enabled; disable it before receiving volume data"
        ));
    }

    let _locks = VolumeLocks::acquire(std::slice::from_ref(&volume), "receive")?;
    ensure_vg()?;

    if lv_exists(&volume.name)? {
        activate_lv(&volume.name)?;
        apply_volume(&volume, true)?;
        if block_device_size(&volume.lv)? < source_bytes {
            return Err(format!(
                "existing target LV {} is smaller than the source snapshot",
                volume.lv
            ));
        }
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
        return Err(format!(
            "target declaration for {volume_id:?} creates a {receiving_bytes}-byte LV, smaller than the {source_bytes}-byte source LV"
        ));
    }

    send_handshake("READY")?;
    let mut device = OpenOptions::new()
        .write(true)
        .open(&receiving_path)
        .map_err(|error| format!("failed to open {}: {error}", receiving_path.display()))?;
    let copied = io::copy(&mut io::stdin().lock().take(source_bytes), &mut device)
        .map_err(|error| format!("failed writing {}: {error}", receiving_path.display()))?;
    if copied != source_bytes {
        return Err(format!(
            "incomplete transfer for {volume_id:?}: received {copied} of {source_bytes} bytes"
        ));
    }
    device
        .sync_all()
        .map_err(|error| format!("failed to flush {}: {error}", receiving_path.display()))?;
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

fn copy_snapshot(volume: &Volume, owner_service: &str, target: &str) -> Result<(), String> {
    let snapshot = lv_path(&snapshot_name(volume)?);
    let source_bytes = block_device_size(&snapshot)?;
    let source_bytes_argument = source_bytes.to_string();
    log::info!(volume = volume.id; "copying {source_bytes} bytes to {target}");

    let mut child = Command::new("ssh")
        .arg(target)
        .args([
            REMOTE_VOLUME,
            "receive",
            owner_service,
            &volume.id,
            "--source-bytes",
            &source_bytes_argument,
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to start receiver on {target}: {error}"))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "failed to read receiver handshake".to_string())?;
    let mut stdout = BufReader::new(stdout);
    let mut handshake = String::new();
    stdout
        .read_line(&mut handshake)
        .map_err(|error| format!("failed to read receiver handshake: {error}"))?;
    drop(stdout);

    let transfer = match handshake.trim() {
        "READY" => {
            let mut input = File::open(&snapshot)
                .map_err(|error| format!("failed to open {}: {error}", snapshot.display()))?;
            let mut remote_input = child
                .stdin
                .take()
                .ok_or_else(|| "failed to open receiver stdin".to_string())?;
            let copied = io::copy(&mut input, &mut remote_input)
                .map_err(|error| format!("failed to stream {}: {error}", snapshot.display()))?;
            drop(remote_input);
            if copied == source_bytes {
                Ok(())
            } else {
                Err(format!(
                    "short read from {}: copied {copied} of {source_bytes} bytes",
                    snapshot.display()
                ))
            }
        }
        "SKIP" => {
            drop(child.stdin.take());
            log::info!(volume = volume.id; "target already contains this volume");
            Ok(())
        }
        response => {
            drop(child.stdin.take());
            Err(format!("unexpected receiver response {response:?}"))
        }
    };

    let status = child
        .wait()
        .map_err(|error| format!("failed to wait for receiver on {target}: {error}"))?;
    if !status.success() {
        return Err(format!(
            "receiver on {target} failed for volume {:?} with {status}",
            volume.id
        ));
    }
    transfer
}

fn create_snapshot(volume: &Volume) -> Result<(), String> {
    let name = snapshot_name(volume)?;
    remove_snapshot(volume, &name)?;
    run_command(
        "lvcreate",
        &[
            "--yes",
            "--snapshot",
            "--permission",
            "r",
            "--extents",
            SNAPSHOT_EXTENTS,
            "--name",
            &name,
            "--addtag",
            "homelab-copy",
            "--addtag",
            &format!("homelab-volume-{}", volume.id),
            &volume.lv,
        ],
    )?;
    run_command("udevadm", &["settle"])
}

fn cleanup_snapshots(volumes: &[Volume]) -> Result<(), String> {
    let mut errors = Vec::new();
    for volume in volumes.iter().rev() {
        match snapshot_name(volume).and_then(|name| remove_snapshot(volume, &name)) {
            Ok(()) => {}
            Err(error) => errors.push(error),
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("\n"))
    }
}

fn remove_snapshot(volume: &Volume, name: &str) -> Result<(), String> {
    if !lv_exists(name)? {
        return Ok(());
    }
    let origin = lv_field(name, "origin")?;
    let tags = lv_field(name, "lv_tags")?;
    if origin != volume.name || !has_tag(&tags, "homelab-copy") {
        return Err(format!(
            "refusing to remove LV {name:?}: expected a homelab-copy snapshot of {:?}",
            volume.name
        ));
    }
    run_command("lvremove", &["--yes", &lv_path(name).to_string_lossy()])
}

fn remove_receiving_lv(volume: &Volume, name: &str) -> Result<(), String> {
    if !lv_exists(name)? {
        return Ok(());
    }
    let path = lv_path(name);
    let tags = lv_field(name, "lv_tags")?;
    if !has_tag(&tags, "homelab-receiving")
        || !has_tag(&tags, &format!("homelab-volume-{}", volume.id))
    {
        return Err(format!(
            "refusing to remove existing LV {name:?}: expected homelab receiving tags"
        ));
    }
    if is_mounted(path.to_string_lossy().as_ref())? {
        return Err(format!("refusing to remove mounted LV {}", path.display()));
    }
    run_command("lvremove", &["--yes", &path.to_string_lossy()])
}

fn activate_lv(name: &str) -> Result<(), String> {
    let path = lv_path(name);
    if !is_block_device(&path) {
        run_command("lvchange", &["--activate", "y", &path.to_string_lossy()])?;
        run_command("udevadm", &["settle"])?;
    }
    Ok(())
}

fn send_handshake(value: &str) -> Result<(), String> {
    let mut stdout = io::stdout().lock();
    writeln!(stdout, "{value}").map_err(|error| format!("failed to write handshake: {error}"))?;
    stdout
        .flush()
        .map_err(|error| format!("failed to flush handshake: {error}"))
}

fn has_tag(tags: &str, expected: &str) -> bool {
    tags.split(',').any(|tag| tag.trim() == expected)
}

fn snapshot_name(volume: &Volume) -> Result<String, String> {
    derived_name(&volume.name, "-copy")
}

fn receiving_name(volume: &Volume) -> Result<String, String> {
    derived_name(&volume.name, "-receiving")
}

fn derived_name(name: &str, suffix: &str) -> Result<String, String> {
    let derived = format!("{name}{suffix}");
    if derived.len() <= 127 {
        Ok(derived)
    } else {
        Err(format!(
            "LV name {name:?} is too long to append migration suffix {suffix:?}"
        ))
    }
}

fn validate_ssh_target(target: &str) -> Result<(), String> {
    let valid = !target.is_empty()
        && !target.starts_with('-')
        && target.chars().all(|character| {
            character.is_ascii_alphanumeric()
                || matches!(character, '.' | '-' | '_' | ':' | '@' | '[' | ']' | '%')
        });
    if valid {
        Ok(())
    } else {
        Err(format!("invalid SSH target {target:?}"))
    }
}

#[cfg(test)]
mod tests {
    use super::{derived_name, validate_ssh_target};

    #[test]
    fn validates_ssh_targets() {
        assert!(validate_ssh_target("copernicus").is_ok());
        assert!(validate_ssh_target("root@10.0.99.8").is_ok());
        assert!(validate_ssh_target("-oProxyCommand=bad").is_err());
        assert!(validate_ssh_target("host;bad").is_err());
    }

    #[test]
    fn validates_derived_lv_name_length() {
        assert_eq!(derived_name("jellyfin", "-copy").unwrap(), "jellyfin-copy");
        assert!(derived_name(&"a".repeat(123), "-copy").is_err());
    }
}
