use anyhow::{bail, ensure, Context, Result};
use std::{
    path::{Path, PathBuf},
    process::Command,
};

use crate::{
    models::Volume,
    util::{command_output, command_stdout, is_mounted, run_command},
};

pub const VG_NAME: &str = "pool";

pub fn ensure_vg() -> Result<()> {
    run_command("vgs", &[VG_NAME]).with_context(|| format!("missing LVM volume group {VG_NAME}"))
}

pub fn lv_exists(name: &str) -> Result<bool> {
    let output = Command::new("lvs")
        .args(["--noheadings", &format!("{VG_NAME}/{name}")])
        .output()
        .with_context(|| format!("failed to query LV {name}"))?;

    match output.status.code() {
        Some(0) => Ok(true),
        Some(5) => Ok(false),
        _ => bail!(
            "lvs failed while querying {name}: {}",
            command_output(&output)
        ),
    }
}

pub fn lv_field(name: &str, field: &str) -> Result<String> {
    command_stdout(
        "lvs",
        &[
            "--noheadings",
            "--options",
            field,
            &format!("{VG_NAME}/{name}"),
        ],
    )
    .with_context(|| format!("failed to query {field} of LV {name}"))
}

pub fn lv_name(path: &str) -> Result<String> {
    Path::new(path)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .with_context(|| format!("invalid LV path {path}"))
}

pub fn lv_path(name: &str) -> PathBuf {
    Path::new("/dev").join(VG_NAME).join(name)
}

pub fn has_tag(tags: &str, expected: &str) -> bool {
    tags.split(',').any(|tag| tag.trim() == expected)
}

pub fn derived_name(name: &str, suffix: &str) -> Result<String> {
    let derived = format!("{name}{suffix}");
    ensure!(
        derived.len() <= 127,
        "LV name {name:?} is too long to append suffix {suffix:?}"
    );
    Ok(derived)
}

/// Create a read-only snapshot of `volume` named `name`. Any existing LV with
/// that name is removed first, provided it is a snapshot of the same origin
/// carrying `tag`. `size` is passed to `--extents` when it is a percentage
/// (for example `20%ORIGIN`) and to `--size` otherwise.
pub fn create_snapshot(volume: &Volume, name: &str, tag: &str, size: &str) -> Result<()> {
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
    )
    .with_context(|| format!("failed to create snapshot {name}"))?;
    run_command("udevadm", &["settle"])
}

/// Remove snapshot `name` of `volume` if it exists. Refuses LVs that are not
/// snapshots of the declared origin tagged with `tag`, and mounted LVs.
pub fn remove_snapshot(volume: &Volume, name: &str, tag: &str) -> Result<()> {
    if !lv_exists(name)? {
        return Ok(());
    }
    let origin = lv_field(name, "origin")?;
    let tags = lv_field(name, "lv_tags")?;
    ensure!(
        origin == volume.name && has_tag(&tags, tag),
        "refusing to remove LV {name:?}: expected a {tag} snapshot of {:?}",
        volume.name
    );
    let path = lv_path(name);
    ensure!(
        !is_mounted(path.to_string_lossy().as_ref())?,
        "refusing to remove mounted snapshot {}",
        path.display()
    );
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
