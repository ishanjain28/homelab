use std::{
    path::{Path, PathBuf},
    process::Command,
};

use crate::util::{command_output, run_command};

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
