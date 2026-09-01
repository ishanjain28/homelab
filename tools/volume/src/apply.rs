use crate::models::{Volume, VolumeSet};
use crate::prompt::confirm;
use crate::table::print_table;
use crate::util::{parse_size, trim_octal};
use std::ffi::CString;
use std::fs;
use std::os::fd::AsRawFd;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};
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
                volume.path.clone(),
                volume.size.clone(),
            ]
        })
        .collect::<Vec<_>>();
    print_table(&["volume", "uuid", "lv", "mount", "size"], &rows);

    for volume in volumes {
        apply_volume(&volume, assume_yes)?;
    }

    Ok(())
}

fn load_volumes(state_file: &Path, volume_ids: &[String]) -> Result<Vec<Volume>, String> {
    let contents = fs::read_to_string(state_file)
        .map_err(|error| format!("failed to read {}: {error}", state_file.display()))?;
    let state = serde_json::from_str::<VolumeSet>(&contents)
        .map_err(|error| format!("failed to parse {}: {error}", state_file.display()))?;

    if volume_ids.is_empty() {
        return Ok(state.volumes.into_values().collect());
    }

    volume_ids
        .iter()
        .map(|id| {
            state
                .volumes
                .get(id)
                .cloned()
                .ok_or_else(|| format!("volume {id:?} is not declared in {}", state_file.display()))
        })
        .collect()
}

fn apply_volume(volume: &Volume, assume_yes: bool) -> Result<(), String> {
    println!();
    println!("[{}] apply", volume.id);

    let expected_size = parse_size(&volume.size)?;
    let lv_name = lv_name(volume)?;

    ensure_vg(volume)?;
    ensure_lv(volume, &lv_name, assume_yes)?;
    ensure_filesystem(volume, assume_yes)?;
    ensure_size(volume, expected_size, assume_yes)?;
    ensure_mount(volume, assume_yes)?;
    ensure_owner(volume, assume_yes)?;

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

fn ensure_lv(volume: &Volume, lv_name: &str, assume_yes: bool) -> Result<(), String> {
    if is_block_device(Path::new(&volume.lv)) {
        return Ok(());
    }

    confirm_or_assume(
        assume_yes,
        &format!("[{}] create {} with size {}", volume.id, volume.lv, volume.size),
    )?;
    run_command(
        "lvcreate",
        &["--yes", "--size", &volume.size, "--name", lv_name, VG_NAME],
    )
}

fn ensure_filesystem(volume: &Volume, assume_yes: bool) -> Result<(), String> {
    let actual_type = command_stdout("blkid", &["-s", "TYPE", "-o", "value", &volume.lv])
        .unwrap_or_default()
        .trim()
        .to_string();

    if actual_type.is_empty() {
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
    } else if actual_type != volume.fs_type {
        return Err(format!(
            "[{}] filesystem type mismatch: expected {}, got {}",
            volume.id, volume.fs_type, actual_type
        ));
    }

    let actual_uuid = command_stdout("blkid", &["-s", "UUID", "-o", "value", &volume.lv])
        .unwrap_or_default()
        .trim()
        .to_string();
    if actual_uuid != volume.uuid {
        return Err(format!(
            "[{}] UUID mismatch: expected {}, got {}",
            volume.id,
            volume.uuid,
            if actual_uuid.is_empty() {
                "missing"
            } else {
                &actual_uuid
            }
        ));
    }

    Ok(())
}

fn ensure_size(volume: &Volume, expected_size: u64, assume_yes: bool) -> Result<(), String> {
    let actual_size = block_device_size(Path::new(&volume.lv))?;

    if actual_size < expected_size {
        confirm_or_assume(
            assume_yes,
            &format!(
                "[{}] grow {} from {} bytes to {}",
                volume.id, volume.lv, actual_size, volume.size
            ),
        )?;
        run_command("lvextend", &["--yes", "--size", &volume.size, &volume.lv])?;
        run_command("resize2fs", &[&volume.lv])?;
    } else if actual_size > expected_size {
        println!("[{}] declared size is smaller than current LV", volume.id);
        println!("  current:  {actual_size} bytes");
        println!("  declared: {expected_size} bytes ({})", volume.size);
        if is_mountpoint(Path::new(&volume.path)) {
            let _ = Command::new("df").args(["-h", &volume.path]).status();
        }
        return Err(format!("[{}] refusing to shrink automatically", volume.id));
    }

    Ok(())
}

fn ensure_mount(volume: &Volume, assume_yes: bool) -> Result<(), String> {
    let mount_path = Path::new(&volume.path);
    if is_mountpoint(mount_path) {
        return Ok(());
    }

    confirm_or_assume(assume_yes, &format!("[{}] mount {}", volume.id, volume.path))?;
    fs::create_dir_all(mount_path)
        .map_err(|error| format!("[{}] failed to create {}: {error}", volume.id, volume.path))?;
    run_command("mount", &[&volume.lv, &volume.path])
}

fn ensure_owner(volume: &Volume, assume_yes: bool) -> Result<(), String> {
    let path = Path::new(&volume.path);
    let metadata = fs::metadata(path)
        .map_err(|error| format!("[{}] failed to stat {}: {error}", volume.id, volume.path))?;
    let actual_mode = metadata.permissions().mode() & 0o7777;
    let expected_mode = u32::from_str_radix(&trim_octal(&volume.owner.mode), 8)
        .map_err(|error| format!("[{}] invalid mode {}: {error}", volume.id, volume.owner.mode))?;

    if metadata.uid() == volume.owner.host_uid && metadata.gid() == volume.owner.host_gid && actual_mode == expected_mode {
        return Ok(());
    }

    confirm_or_assume(
        assume_yes,
        &format!(
            "[{}] set {} owner={}:{} mode={}",
            volume.id, volume.path, volume.owner.host_uid, volume.owner.host_gid, volume.owner.mode
        ),
    )?;

    chown(path, volume.owner.host_uid, volume.owner.host_gid)?;
    fs::set_permissions(path, fs::Permissions::from_mode(expected_mode))
        .map_err(|error| format!("[{}] failed to chmod {}: {error}", volume.id, volume.path))?;
    Ok(())
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

fn command_stdout(program: &str, args: &[&str]) -> Result<String, String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| format!("failed to run {program}: {error}"))?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

fn run_command(program: &str, args: &[&str]) -> Result<(), String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| format!("failed to run {program}: {error}"))?;
    if output.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
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

fn is_mountpoint(path: &Path) -> bool {
    let Ok(mountinfo) = fs::read_to_string("/proc/self/mountinfo") else {
        return false;
    };
    let wanted = path.to_string_lossy();

    mountinfo.lines().any(|line| {
        let fields = line.split_whitespace().collect::<Vec<_>>();
        fields.get(4).is_some_and(|mountpoint| *mountpoint == wanted)
    })
}

fn chown(path: &Path, uid: u32, gid: u32) -> Result<(), String> {
    let c_path = CString::new(path.as_os_str().as_bytes())
        .map_err(|_| format!("path contains NUL byte: {}", path.display()))?;
    let result = unsafe { libc::chown(c_path.as_ptr(), uid, gid) };
    if result == 0 {
        Ok(())
    } else {
        Err(format!(
            "failed to chown {}: {}",
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
