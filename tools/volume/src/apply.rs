use crate::models::{Context, Volume};
use crate::nix::{hosts, volumes};
use crate::prompt::confirm;
use crate::remote::{remote, remote_status};
use crate::table::print_host_header;
use crate::util::{parse_u64, trim_octal};

pub fn run_apply(context: &Context, requested_hosts: &[String]) -> Result<(), String> {
    for host in hosts(context, requested_hosts)? {
        print_host_header(&host);
        let declared = volumes(context, &host)?;
        if declared.is_empty() {
            println!("no homelab volumes declared for {host}");
            continue;
        }

        for volume in declared {
            println!("[{host}/{}] apply", volume.id);
            match apply_volume(context, &host, &volume) {
                Ok(()) => println!("[{host}/{}] ok", volume.id),
                Err(error) => {
                    eprintln!("[{host}/{}] failed: {error}", volume.id);
                    return Err("volume apply failed".to_string());
                }
            }
        }
    }
    Ok(())
}

fn apply_volume(context: &Context, host: &str, volume: &Volume) -> Result<(), String> {
    let expected_size = remote(context, host, &["numfmt", "--from=iec", &volume.size])?
        .trim()
        .to_string();
    let lv_name = volume
        .lv
        .rsplit('/')
        .next()
        .ok_or_else(|| format!("[{host}/{}] invalid LV path {}", volume.id, volume.lv))?;

    if !remote_status(context, host, &["vgs", "pool"])? {
        return Err(format!("[{host}/{}] missing LVM volume group: pool", volume.id));
    }

    if !remote_status(context, host, &["test", "-b", &volume.lv])? {
        if confirm(&format!(
            "[{host}/{}] create {} with size {}",
            volume.id, volume.lv, volume.size
        ))? {
            remote(
                context,
                host,
                &["lvcreate", "--yes", "--size", &volume.size, "--name", lv_name, "pool"],
            )?;
        } else {
            return Err(format!("[{host}/{}] skipped missing LV", volume.id));
        }
    }

    let actual_type = remote(context, host, &["blkid", "-s", "TYPE", "-o", "value", &volume.lv])
        .unwrap_or_default()
        .trim()
        .to_string();
    if actual_type.is_empty() {
        if confirm(&format!(
            "[{host}/{}] create {} filesystem on {} with UUID {}",
            volume.id, volume.fs_type, volume.lv, volume.uuid
        ))? {
            remote(
                context,
                host,
                &[
                    &format!("mkfs.{}", volume.fs_type),
                    "-F",
                    "-U",
                    &volume.uuid,
                    &volume.lv,
                ],
            )?;
        } else {
            return Err(format!("[{host}/{}] skipped missing filesystem", volume.id));
        }
    } else if actual_type != volume.fs_type {
        return Err(format!(
            "[{host}/{}] filesystem type mismatch: expected {}, got {}",
            volume.id, volume.fs_type, actual_type
        ));
    }

    let actual_uuid = remote(context, host, &["blkid", "-s", "UUID", "-o", "value", &volume.lv])
        .unwrap_or_default()
        .trim()
        .to_string();
    if actual_uuid != volume.uuid {
        return Err(format!(
            "[{host}/{}] UUID mismatch: expected {}, got {}",
            volume.id,
            volume.uuid,
            if actual_uuid.is_empty() { "missing" } else { &actual_uuid }
        ));
    }

    let actual_size = remote(context, host, &["blockdev", "--getsize64", &volume.lv])?
        .trim()
        .to_string();
    let actual_size_u64 = parse_u64(&actual_size, host, &volume.id, "actual size")?;
    let expected_size_u64 = parse_u64(&expected_size, host, &volume.id, "expected size")?;

    if actual_size_u64 < expected_size_u64 {
        if confirm(&format!(
            "[{host}/{}] grow {} from {} bytes to {}",
            volume.id, volume.lv, actual_size, volume.size
        ))? {
            remote(context, host, &["lvextend", "--yes", "--size", &volume.size, &volume.lv])?;
            remote(context, host, &["resize2fs", &volume.lv])?;
        } else {
            return Err(format!("[{host}/{}] skipped LV growth", volume.id));
        }
    } else if actual_size_u64 > expected_size_u64 {
        println!("[{host}/{}] declared size is smaller than current LV", volume.id);
        println!("  current:  {actual_size} bytes");
        println!("  declared: {expected_size} bytes ({})", volume.size);
        if remote_status(context, host, &["findmnt", "-rn", "--mountpoint", &volume.path])? {
            print!("{}", remote(context, host, &["df", "-h", &volume.path])?);
        } else {
            println!("  usage: unavailable because {} is not mounted", volume.path);
        }
        return Err(format!("[{host}/{}] refusing to shrink automatically", volume.id));
    }

    ensure_mount_owner(context, host, volume)
}

fn ensure_mount_owner(context: &Context, host: &str, volume: &Volume) -> Result<(), String> {
    if !remote_status(context, host, &["findmnt", "-rn", "--mountpoint", &volume.path])? {
        if confirm(&format!("[{host}/{}] mount {}", volume.id, volume.path))? {
            remote(context, host, &["mkdir", "-p", &volume.path])?;
            remote(context, host, &["mount", &volume.lv, &volume.path])?;
        } else {
            return Err(format!("[{host}/{}] skipped mount", volume.id));
        }
    }

    let actual_owner = remote(context, host, &["stat", "-c", "%u:%g", &volume.path])
        .unwrap_or_default()
        .trim()
        .to_string();
    let actual_mode = remote(context, host, &["stat", "-c", "%a", &volume.path])
        .unwrap_or_default()
        .trim()
        .to_string();
    let expected_mode = trim_octal(&volume.mode);
    let expected_owner = format!("{}:{}", volume.host_uid, volume.host_gid);

    if actual_owner != expected_owner || actual_mode != expected_mode {
        if confirm(&format!(
            "[{host}/{}] set {} owner={} mode={}",
            volume.id, volume.path, expected_owner, volume.mode
        ))? {
            remote(context, host, &["chown", &expected_owner, &volume.path])?;
            remote(context, host, &["chmod", &volume.mode, &volume.path])?;
        } else {
            return Err(format!("[{host}/{}] skipped ownership/mode fix", volume.id));
        }
    }

    Ok(())
}

