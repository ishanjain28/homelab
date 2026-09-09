use crate::models::{load_volumes, Volume};
use crate::prompt::confirm;
use crate::table::print_table;
use crate::util::parse_size;
use std::fs;
use std::os::fd::AsRawFd;
use std::os::unix::fs::FileTypeExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const VG_NAME: &str = "pool";

pub fn run_apply(state_file: &Path, assume_yes: bool, volume_ids: &[String]) -> Result<(), String> {
    let volumes = load_volumes(state_file, volume_ids)?;

    if volumes.is_empty() {
        println!("no matching homelab volumes declared");
        return Ok(());
    }

    let rows = volumes
        .iter()
        .map(|volume| {
            vec![
                volume.id.clone(),
                volume.uuid.clone(),
                volume.lv.clone(),
                volume.size.clone(),
            ]
        })
        .collect::<Vec<_>>();
    print_table(&["volume", "uuid", "lv", "size"], &rows);

    for volume in volumes {
        apply_volume(&volume, assume_yes)?;
    }

    Ok(())
}

fn apply_volume(volume: &Volume, assume_yes: bool) -> Result<(), String> {
    println!();
    println!("[{}] apply", volume.id);

    let expected_size = parse_size(&volume.size)?;
    let lv_name = lv_name(volume)?;

    ensure_vg(volume)?;
    let lv_created = ensure_lv(volume, &lv_name, assume_yes)?;
    ensure_filesystem(volume, assume_yes, lv_created)?;
    ensure_size(volume, expected_size, assume_yes)?;

    println!("[{}] ok", volume.id);
    Ok(())
}

fn ensure_vg(volume: &Volume) -> Result<(), String> {
    if command_status("vgs", &[VG_NAME])? {
        Ok(())
    } else {
        Err(format!("[{}] missing LVM volume group: {VG_NAME}", volume.id))
    }
}

fn ensure_lv(volume: &Volume, lv_name: &str, assume_yes: bool) -> Result<bool, String> {
    if is_block_device(Path::new(&volume.lv)) {
        return Ok(false);
    }

    confirm_or_assume(
        assume_yes,
        &format!("[{}] create {} with size {}", volume.id, volume.lv, volume.size),
    )?;
    run_command(
        "lvcreate",
        &["--yes", "--size", &volume.size, "--name", lv_name, VG_NAME],
    )?;
    Ok(true)
}

fn ensure_filesystem(volume: &Volume, assume_yes: bool, lv_created: bool) -> Result<(), String> {
    let mut filesystem = probe_filesystem(volume)?;

    if filesystem.is_none() {
        if assume_yes && !lv_created {
            return Err(format!(
                "[{}] no filesystem detected on existing LV {}; refusing to format unattended. Run volume apply {} interactively to confirm",
                volume.id, volume.lv, volume.id
            ));
        }
        confirm_or_assume(
            assume_yes,
            &format!(
                "[{}] create {} filesystem on {} with UUID {}",
                volume.id, volume.fs_type, volume.lv, volume.uuid
            ),
        )?;
        run_command(
            &format!("mkfs.{}", volume.fs_type),
            &["-F", "-U", &volume.uuid, &volume.lv],
        )?;
        filesystem = probe_filesystem(volume)?;
    }

    let (actual_type, actual_uuid) = filesystem.ok_or_else(|| {
        format!(
            "[{}] no filesystem detected on {} after formatting",
            volume.id, volume.lv
        )
    })?;
    if actual_type != volume.fs_type {
        return Err(format!(
            "[{}] filesystem type mismatch: expected {}, got {}",
            volume.id, volume.fs_type, actual_type
        ));
    }
    if actual_uuid.as_deref() != Some(volume.uuid.as_str()) {
        return Err(format!(
            "[{}] UUID mismatch: expected {}, got {}",
            volume.id,
            volume.uuid,
            actual_uuid.as_deref().unwrap_or("missing")
        ));
    }

    Ok(())
}

fn probe_filesystem(volume: &Volume) -> Result<Option<(String, Option<String>)>, String> {
    let output = Command::new("blkid")
        .args(["--probe", "--output", "export", &volume.lv])
        .output()
        .map_err(|error| format!("[{}] failed to run blkid: {error}", volume.id))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    classify_filesystem_probe(
        &volume.id,
        &volume.lv,
        output.status.code(),
        &stdout,
        &stderr,
    )
}

fn classify_filesystem_probe(
    volume_id: &str,
    volume_path: &str,
    status: Option<i32>,
    stdout: &str,
    stderr: &str,
) -> Result<Option<(String, Option<String>)>, String> {
    if status == Some(0) {
        let value = |key: &str| {
            stdout
                .lines()
                .find_map(|line| line.strip_prefix(&format!("{key}=")))
                .map(str::to_string)
        };
        let fs_type = value("TYPE").ok_or_else(|| {
            format!(
                "[{}] blkid succeeded for {} but returned no filesystem type",
                volume_id, volume_path
            )
        })?;
        return Ok(Some((fs_type, value("UUID"))));
    }

    if status == Some(2) && stdout.trim().is_empty() && stderr.trim().is_empty() {
        return Ok(None);
    }

    Err(format!(
        "[{}] failed to probe filesystem on {} with blkid (status {}): {}",
        volume_id,
        volume_path,
        status.map_or_else(|| "signal".to_string(), |code| code.to_string()),
        if stderr.trim().is_empty() {
            "no error output"
        } else {
            stderr.trim()
        }
    ))
}

fn ensure_size(volume: &Volume, expected_size: u64, assume_yes: bool) -> Result<(), String> {
    let actual_size = block_device_size(Path::new(&volume.lv))?;

    if is_mounted(&volume.lv)? {
        return Err(format!(
            "[{}] refusing to reconcile the size of mounted volume {}; stop its service and unmount it first",
            volume.id, volume.lv
        ));
    }

    if actual_size < expected_size {
        confirm_or_assume(
            assume_yes,
            &format!(
                "[{}] grow {} from {} bytes to {}",
                volume.id, volume.lv, actual_size, volume.size
            ),
        )?;
        run_command("lvextend", &["--yes", "--size", &volume.size, &volume.lv])?;
    } else if actual_size > expected_size {
        println!(
            "[{}] LV is larger than its declared minimum; leaving it unchanged",
            volume.id
        );
        println!("  current:  {actual_size} bytes");
        println!("  declared: {expected_size} bytes ({})", volume.size);
    }

    grow_ext4_to_device(volume)
}

fn grow_ext4_to_device(volume: &Volume) -> Result<(), String> {
    let first_attempt = run_command("resize2fs", &[&volume.lv]);
    let error = match first_attempt {
        Ok(()) => return Ok(()),
        Err(error) => error,
    };

    if !error.contains("e2fsck -f") {
        return Err(error);
    }

    println!(
        "[{}] filesystem requires a check before resize; running e2fsck",
        volume.id
    );
    run_e2fsck(volume)?;
    run_command("resize2fs", &[&volume.lv])
}

fn is_mounted(device: &str) -> Result<bool, String> {
    let output = Command::new("findmnt")
        .args(["--noheadings", "--source", device])
        .output()
        .map_err(|error| format!("failed to run findmnt: {error}"))?;

    match output.status.code() {
        Some(0) => Ok(true),
        Some(1) => Ok(false),
        status => Err(format!(
            "findmnt failed while checking {device} (status {}): {}",
            status.map_or_else(|| "signal".to_string(), |code| code.to_string()),
            String::from_utf8_lossy(&output.stderr).trim()
        )),
    }
}

fn run_e2fsck(volume: &Volume) -> Result<(), String> {
    let output = Command::new("e2fsck")
        .args(["-f", "-p", &volume.lv])
        .output()
        .map_err(|error| format!("failed to run e2fsck: {error}"))?;

    match output.status.code() {
        Some(0 | 1) => Ok(()),
        status => Err(format!(
            "[{}] e2fsck failed for {} (status {}): {}",
            volume.id,
            volume.lv,
            status.map_or_else(|| "signal".to_string(), |code| code.to_string()),
            command_output(&output)
        )),
    }
}

fn lv_name(volume: &Volume) -> Result<String, String> {
    PathBuf::from(&volume.lv)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .ok_or_else(|| format!("[{}] invalid LV path {}", volume.id, volume.lv))
}

fn confirm_or_assume(assume_yes: bool, prompt: &str) -> Result<(), String> {
    if assume_yes || confirm(prompt)? {
        Ok(())
    } else {
        Err(format!("{prompt}: skipped"))
    }
}

fn command_status(program: &str, args: &[&str]) -> Result<bool, String> {
    Command::new(program)
        .args(args)
        .status()
        .map(|status| status.success())
        .map_err(|error| format!("failed to run {program}: {error}"))
}

fn run_command(program: &str, args: &[&str]) -> Result<(), String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| format!("failed to run {program}: {error}"))?;
    if output.status.success() {
        Ok(())
    } else {
        Err(command_output(&output))
    }
}

fn command_output(output: &std::process::Output) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    [stdout.trim(), stderr.trim()]
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

fn block_device_size(path: &Path) -> Result<u64, String> {
    const BLKGETSIZE64: libc::c_ulong = 0x8008_1272;

    let file = fs::File::open(path).map_err(|error| format!("failed to open {}: {error}", path.display()))?;
    let mut size = 0_u64;
    let result = unsafe { libc::ioctl(file.as_raw_fd(), BLKGETSIZE64, &mut size) };
    if result == 0 {
        Ok(size)
    } else {
        Err(format!(
            "failed to get block size for {}: {}",
            path.display(),
            std::io::Error::last_os_error()
        ))
    }
}

fn is_block_device(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| metadata.file_type().is_block_device())
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::classify_filesystem_probe;

    #[test]
    fn classifies_detected_filesystem() {
        let result = classify_filesystem_probe(
            "data",
            "/dev/pool/data",
            Some(0),
            "DEVNAME=/dev/pool/data\nUUID=test-uuid\nTYPE=ext4\n",
            "",
        )
        .unwrap();

        assert_eq!(result, Some(("ext4".to_string(), Some("test-uuid".to_string()))));
    }

    #[test]
    fn classifies_clean_no_signature_result() {
        assert_eq!(
            classify_filesystem_probe("data", "/dev/pool/data", Some(2), "", "").unwrap(),
            None
        );
    }

    #[test]
    fn rejects_probe_errors() {
        let error = classify_filesystem_probe(
            "data",
            "/dev/pool/data",
            Some(4),
            "",
            "permission denied",
        )
        .unwrap_err();

        assert!(error.contains("permission denied"));
    }

    #[test]
    fn rejects_ambiguous_probe_results() {
        let error = classify_filesystem_probe("data", "/dev/pool/data", Some(8), "", "").unwrap_err();

        assert!(error.contains("status 8"));
    }

    #[test]
    fn rejects_success_without_filesystem_type() {
        let error = classify_filesystem_probe(
            "data",
            "/dev/pool/data",
            Some(0),
            "DEVNAME=/dev/pool/data\nUUID=test-uuid\n",
            "",
        )
        .unwrap_err();

        assert!(error.contains("returned no filesystem type"));
    }
}
