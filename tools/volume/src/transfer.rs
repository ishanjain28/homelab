use anyhow::{bail, ensure, Context, Result};
use std::{
    fs::{File, OpenOptions},
    io::{self, BufRead, BufReader, ErrorKind, Read, Write},
    path::Path,
    process::{Command, Stdio},
    time::{Duration, Instant},
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
    util::{
        block_device_size, install_interrupt_handler, interrupted, is_block_device, is_mounted,
        run_command,
    },
};

const SNAPSHOT_TAG: &str = "homelab-copy";
const RECEIVING_TAG: &str = "homelab-receiving";
const REMOTE_VOLUME: &str = "/run/current-system/sw/bin/volume";
const CHUNK_SIZE: usize = 4 << 20;
const PROGRESS_INTERVAL: Duration = Duration::from_secs(10);

/// Pull every volume owned by a service from another host. Runs on the destination as root and
/// starts `volume send` on the source through `ssh <source> sudo -n`.
pub fn run_pull(state_file: &Path, owner_service: &str, source: &str) -> Result<()> {
    validate_ssh_target(source)?;
    install_interrupt_handler();

    let state = load_state(state_file)?;
    let volumes = service_volumes(&state, owner_service)?;
    ensure!(
        volumes.iter().all(|volume| !volume.owner_enabled),
        "service {owner_service:?} is enabled on {}; disable it before pulling its volumes",
        state.host
    );

    let _locks = VolumeLocks::acquire(&volumes, "pull")?;
    ensure_vg()?;

    let mut missing = Vec::new();
    for volume in &volumes {
        if lv_exists(&volume.name)? {
            activate_lv(&volume.name)?;
            apply_volume(volume, true)?;
            log::info!(volume = volume.id; "already present, skipping");
        } else {
            missing.push(volume);
        }
    }
    if missing.is_empty() {
        return Ok(());
    }

    let mut sender = Command::new("ssh")
        .arg(source)
        .args(["sudo", "-n", REMOTE_VOLUME, "send", owner_service])
        .args(missing.iter().map(|volume| volume.id.as_str()))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to start sender on {source}"))?;
    let mut stream = BufReader::with_capacity(
        CHUNK_SIZE,
        sender.stdout.take().context("sender has no stdout")?,
    );

    let mut result = Ok(());
    for volume in &missing {
        result = receive_volume(volume, &mut stream)
            .with_context(|| format!("[{}] pull failed", volume.id));
        if result.is_err() {
            break;
        }
    }
    if result.is_err() {
        let _ = sender.kill();
    }
    drop(stream);
    let status = sender
        .wait()
        .with_context(|| format!("failed to wait for sender on {source}"))?;
    result?;
    ensure!(status.success(), "sender on {source} failed with {status}");
    Ok(())
}

/// Snapshot the requested volumes of a service and write them to stdout, each preceded by a
/// `VOLUME <id> <bytes>` line. Invoked by `volume pull` over SSH; logs go to stderr.
pub fn run_send(state_file: &Path, owner_service: &str, volume_ids: &[String]) -> Result<()> {
    install_interrupt_handler();

    let state = load_state(state_file)?;
    let owned = service_volumes(&state, owner_service)?;
    let volumes = volume_ids
        .iter()
        .map(|id| {
            owned
                .iter()
                .find(|volume| &volume.id == id)
                .cloned()
                .with_context(|| {
                    format!("{owner_service:?} owns no volume {id:?} on {}", state.host)
                })
        })
        .collect::<Result<Vec<_>>>()?;

    let _locks = VolumeLocks::acquire(&volumes, "send")?;
    for volume in &volumes {
        validate_volume(volume).with_context(|| format!("[{}] validation failed", volume.id))?;
    }

    let result = snapshot_and_send(&volumes);
    let cleanup = cleanup_snapshots(&volumes);
    match (result, cleanup) {
        (Err(error), Err(cleanup_error)) => {
            Err(error.context(format!("snapshot cleanup also failed: {cleanup_error:#}")))
        }
        (result, cleanup) => result.and(cleanup),
    }
}

fn snapshot_and_send(volumes: &[Volume]) -> Result<()> {
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

    let mut output = io::stdout().lock();
    for volume in volumes {
        let snapshot = lv_path(&snapshot_name(volume)?);
        let bytes = block_device_size(&snapshot)?;
        writeln!(output, "VOLUME {} {bytes}", volume.id).context("failed to write header")?;
        let mut input = File::open(&snapshot)
            .with_context(|| format!("failed to open {}", snapshot.display()))?;
        copy_exact(&mut input, &mut output, bytes, &volume.id)
            .with_context(|| format!("[{}] send failed", volume.id))?;
        output.flush().context("failed to flush stdout")?;
    }
    Ok(())
}

fn receive_volume(volume: &Volume, stream: &mut impl BufRead) -> Result<()> {
    let source_bytes = read_header(stream, &volume.id)?;
    let receiving_name = receiving_name(volume)?;
    remove_receiving_lv(volume, &receiving_name)?;
    run_command(
        "lvcreate",
        &[
            "--yes",
            "--size",
            &volume.size,
            "--name",
            &receiving_name,
            "--addtag",
            RECEIVING_TAG,
            "--addtag",
            &format!("homelab-volume-{}", volume.id),
            VG_NAME,
        ],
    )?;
    run_command("udevadm", &["settle"])?;

    let result = fill_and_rename(volume, &receiving_name, source_bytes, stream);
    if result.is_err() {
        if let Err(error) = remove_receiving_lv(volume, &receiving_name) {
            log::error!(volume = volume.id; "failed to remove {receiving_name}: {error:#}");
        }
    }
    result
}

fn fill_and_rename(
    volume: &Volume,
    receiving_name: &str,
    source_bytes: u64,
    stream: &mut impl Read,
) -> Result<()> {
    let receiving_path = lv_path(receiving_name);
    let receiving_bytes = block_device_size(&receiving_path)?;
    ensure!(
        receiving_bytes >= source_bytes,
        "declared size creates a {receiving_bytes}-byte LV, smaller than the {source_bytes}-byte source"
    );

    let mut device = OpenOptions::new()
        .write(true)
        .open(&receiving_path)
        .with_context(|| format!("failed to open {}", receiving_path.display()))?;
    copy_exact(stream, &mut device, source_bytes, &volume.id)?;
    device
        .sync_all()
        .with_context(|| format!("failed to flush {}", receiving_path.display()))?;
    drop(device);

    let mut received = volume.clone();
    received.name = receiving_name.to_string();
    received.lv = receiving_path.to_string_lossy().into_owned();
    run_e2fsck(&received)?;
    ensure_filesystem(&received)?;
    if receiving_bytes > source_bytes {
        grow_ext4_to_device(&received)?;
        ensure_filesystem(&received)?;
    }

    run_command("lvrename", &[VG_NAME, receiving_name, &volume.name])?;
    run_command("udevadm", &["settle"])?;
    ensure_filesystem(volume)
}

fn read_header(stream: &mut impl BufRead, volume_id: &str) -> Result<u64> {
    let mut line = String::new();
    stream
        .read_line(&mut line)
        .context("failed to read volume header from sender")?;
    let fields: Vec<&str> = line.split_whitespace().collect();
    match fields.as_slice() {
        ["VOLUME", id, bytes] if *id == volume_id => bytes
            .parse()
            .with_context(|| format!("invalid size in volume header {line:?}")),
        [] => bail!("sender closed the stream before {volume_id:?}"),
        _ => bail!("unexpected volume header {:?}, expected {volume_id:?}", line.trim()),
    }
}

/// Copy exactly `bytes` bytes, stopping early on SIGINT/SIGTERM/SIGHUP and logging progress.
fn copy_exact(
    reader: &mut impl Read,
    writer: &mut impl Write,
    bytes: u64,
    volume_id: &str,
) -> Result<()> {
    let mut buffer = vec![0; CHUNK_SIZE];
    let mut copied = 0;
    let started = Instant::now();
    let mut last_report = started;

    while copied < bytes {
        ensure!(!interrupted(), "interrupted after {copied} of {bytes} bytes");
        let wanted = buffer.len().min((bytes - copied) as usize);
        let read = match reader.read(&mut buffer[..wanted]) {
            Ok(0) => bail!("stream ended after {copied} of {bytes} bytes"),
            Ok(read) => read,
            Err(error) if error.kind() == ErrorKind::Interrupted => continue,
            Err(error) => return Err(error).context("read failed"),
        };
        writer.write_all(&buffer[..read]).context("write failed")?;
        copied += read as u64;

        if last_report.elapsed() >= PROGRESS_INTERVAL {
            last_report = Instant::now();
            let rate = copied as f64 / started.elapsed().as_secs_f64() / (1 << 20) as f64;
            log::info!(
                volume = volume_id;
                "{} / {} MiB ({rate:.0} MiB/s)", copied >> 20, bytes >> 20
            );
        }
    }
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
        has_tag(&tags, RECEIVING_TAG) && has_tag(&tags, &format!("homelab-volume-{}", volume.id)),
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
    use super::{copy_exact, read_header, validate_ssh_target};
    use std::io::Cursor;

    #[test]
    fn validates_ssh_targets() {
        assert!(validate_ssh_target("copernicus").is_ok());
        assert!(validate_ssh_target("root@10.0.99.8").is_ok());
        assert!(validate_ssh_target("-oProxyCommand=bad").is_err());
        assert!(validate_ssh_target("host;bad").is_err());
    }

    #[test]
    fn parses_volume_headers() {
        let mut stream = Cursor::new(b"VOLUME gitea 1024\n".to_vec());
        assert_eq!(read_header(&mut stream, "gitea").unwrap(), 1024);
        assert!(read_header(&mut Cursor::new(b"VOLUME loki 1\n".to_vec()), "gitea").is_err());
        assert!(read_header(&mut Cursor::new(Vec::new()), "gitea").is_err());
    }

    #[test]
    fn copies_exactly_and_rejects_short_streams() {
        let mut output = Vec::new();
        copy_exact(&mut Cursor::new(vec![7; 10]), &mut output, 6, "x").unwrap();
        assert_eq!(output, vec![7; 6]);
        assert!(copy_exact(&mut Cursor::new(vec![7; 3]), &mut Vec::new(), 6, "x").is_err());
    }
}
