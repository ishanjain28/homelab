use std::{
    path::{Path, PathBuf},
    process::Command,
};

use crate::{
    models::Volume,
    util::{command_output, is_mounted, run_command},
};

pub const VG_NAME: &str = "pool";

pub fn ensure_vg() -> Result<(), String> {
    if run_command("vgs", &[VG_NAME]).is_ok() {
        Ok(())
    } else {
        Err(format!("missing LVM volume group: {VG_NAME}"))
    }
}

pub fn lv_exists(name: &str) -> Result<bool, String> {
    let output = Command::new("lvs")
        .args(["--noheadings", &format!("{VG_NAME}/{name}")])
        .output()
        .map_err(|error| format!("failed to query LV {name}: {error}"))?;

    match output.status.code() {
        Some(0) => Ok(true),
        Some(5) => Ok(false),
        _ => Err(format!(
            "lvs failed while querying {name}: {}",
            command_output(&output)
        )),
    }
}

pub fn lv_field(name: &str, field: &str) -> Result<String, String> {
    let output = Command::new("lvs")
        .args([
            "--noheadings",
            "--options",
            field,
            &format!("{VG_NAME}/{name}"),
        ])
        .output()
        .map_err(|error| format!("failed to query {field} for LV {name}: {error}"))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(format!(
            "lvs failed while querying {field} for LV {name}: {}",
            command_output(&output)
        ))
    }
}

pub fn lv_name(path: &str) -> Result<String, String> {
    Path::new(path)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .ok_or_else(|| format!("invalid LV path {path}"))
}

pub fn lv_path(name: &str) -> PathBuf {
    Path::new("/dev").join(VG_NAME).join(name)
}

pub fn has_tag(tags: &str, expected: &str) -> bool {
    tags.split(',').any(|tag| tag.trim() == expected)
}

pub fn derived_name(name: &str, suffix: &str) -> Result<String, String> {
    let derived = format!("{name}{suffix}");
    if derived.len() <= 127 {
        Ok(derived)
    } else {
        Err(format!(
            "LV name {name:?} is too long to append suffix {suffix:?}"
        ))
    }
}

/// Create a read-only snapshot of `volume` named `name`. Any existing LV with
/// that name is removed first, provided it is a snapshot of the same origin
/// carrying `tag`. `size` is passed to `--extents` when it is a percentage
/// (for example `20%ORIGIN`) and to `--size` otherwise.
pub fn create_snapshot(volume: &Volume, name: &str, tag: &str, size: &str) -> Result<(), String> {
    remove_snapshot(volume, name, tag)?;
    let size_flag = if size.contains('%') {
        "--extents"
    } else {
        "--size"
    };
    run_command(
        "lvcreate",
        &[
            "--yes",
            "--snapshot",
            "--permission",
            "r",
            size_flag,
            size,
            "--name",
            name,
            "--addtag",
            tag,
            "--addtag",
            &format!("homelab-volume-{}", volume.id),
            &volume.lv,
        ],
    )?;
    run_command("udevadm", &["settle"])
}

/// Remove snapshot `name` of `volume` if it exists. Refuses LVs that are not
/// snapshots of the declared origin tagged with `tag`, and mounted LVs.
pub fn remove_snapshot(volume: &Volume, name: &str, tag: &str) -> Result<(), String> {
    if !lv_exists(name)? {
        return Ok(());
    }
    let origin = lv_field(name, "origin")?;
    let tags = lv_field(name, "lv_tags")?;
    if origin != volume.name || !has_tag(&tags, tag) {
        return Err(format!(
            "refusing to remove LV {name:?}: expected a {tag} snapshot of {:?}",
            volume.name
        ));
    }
    let path = lv_path(name);
    if is_mounted(path.to_string_lossy().as_ref())? {
        return Err(format!(
            "refusing to remove mounted snapshot {}",
            path.display()
        ));
    }
    run_command("lvremove", &["--yes", &path.to_string_lossy()])
}

#[cfg(test)]
mod tests {
    use super::{derived_name, has_tag};

    #[test]
    fn validates_derived_lv_name_length() {
        assert_eq!(derived_name("jellyfin", "-copy").unwrap(), "jellyfin-copy");
        assert!(derived_name(&"a".repeat(123), "-copy").is_err());
    }

    #[test]
    fn matches_tags() {
        assert!(has_tag("homelab-copy,homelab-volume-x", "homelab-copy"));
        assert!(!has_tag("homelab-copy-2", "homelab-copy"));
    }
}
