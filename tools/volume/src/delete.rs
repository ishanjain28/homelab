use crate::models::{Context, Volume};
use crate::nix::volumes;
use crate::prompt::{confirm, confirm_exact};
use crate::remote::{remote, remote_script, remote_status};

pub fn run_delete(context: &Context, host: &str, volume_ids: &[String]) -> Result<(), String> {
    if volume_ids.is_empty() {
        return Err("delete requires at least one volume id".to_string());
    }

    let declared = volumes(context, host)?;

    for wanted_id in volume_ids {
        let volume = declared
            .iter()
            .find(|volume| volume.id == *wanted_id)
            .ok_or_else(|| format!("[{host}/{wanted_id}] no declared volume found"))?;
        delete_volume(context, host, volume)?;
    }

    Ok(())
}

fn delete_volume(context: &Context, host: &str, volume: &Volume) -> Result<(), String> {
    if !remote_status(context, host, &["test", "-b", &volume.lv])? {
        return Err(format!("[{host}/{}] missing block device: {}", volume.id, volume.lv));
    }

    let actual_type = remote(context, host, &["blkid", "-s", "TYPE", "-o", "value", &volume.lv])
        .unwrap_or_default()
        .trim()
        .to_string();
    if actual_type != volume.fs_type {
        return Err(format!(
            "[{host}/{}] filesystem type mismatch: expected {}, got {}",
            volume.id,
            volume.fs_type,
            if actual_type.is_empty() { "missing" } else { &actual_type }
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

    if !remote_status(context, host, &["findmnt", "-rn", "--mountpoint", &volume.path])? {
        if confirm(&format!(
            "[{host}/{}] mount {} at {} to inspect whether it is empty",
            volume.id, volume.lv, volume.path
        ))? {
            remote(context, host, &["mkdir", "-p", &volume.path])?;
            remote(context, host, &["mount", &volume.lv, &volume.path])?;
        } else {
            return Err(format!("[{host}/{}] skipped mount for delete", volume.id));
        }
    }

    println!("[{host}/{}] current usage", volume.id);
    print!("{}", remote(context, host, &["df", "-h", &volume.path])?);

    let allocated = remote(context, host, &["blockdev", "--getsize64", &volume.lv])?;
    println!("allocated bytes: {}", allocated.trim());
    let used = remote_script(
        context,
        host,
        r#"df -B1 --output=used "$1" | tail -n 1 | tr -d " ""#,
        &[&volume.path],
    )?;
    println!("used bytes: {}", used.trim());

    let find_script = r#"find "$1" -mindepth 1 ! -name lost+found -print -quit | grep -q ."#;
    if remote_script(context, host, find_script, &[&volume.path]).is_ok() {
        eprintln!("[{host}/{}] refusing to delete: volume is not empty", volume.id);
        let listing_script = r#"find "$1" -mindepth 1 ! -name lost+found -maxdepth 2 -print | sed -n "1,20p""#;
        let _ = remote_script(context, host, listing_script, &[&volume.path]);
        return Err(format!("[{host}/{}] volume is not empty", volume.id));
    }

    let expected = format!("delete {host}/{}", volume.id);
    if confirm_exact(
        &format!(
            "[{host}/{}] delete {}. This stops container@{}, unmounts {}, and removes the LV.",
            volume.id, volume.lv, volume.owner_service, volume.path
        ),
        &expected,
    )? {
        remote(
            context,
            host,
            &["systemctl", "stop", &format!("container@{}.service", volume.owner_service)],
        )?;
        remote(context, host, &["umount", &volume.path])?;
        remote(context, host, &["lvremove", "--yes", &volume.lv])?;
        Ok(())
    } else {
        Err(format!("[{host}/{}] delete cancelled", volume.id))
    }
}

