use crate::models::{load_volume, load_volumes, Volume};
use crate::table::print_table;
use crate::util::parse_size;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

pub fn run_snapshot_create(
    state_file: &Path,
    volume_id: &str,
    size: &str,
    requested_name: Option<&str>,
) -> Result<(), String> {
    let volume = load_volume(state_file, volume_id)?;
    if parse_size(size)? == 0 {
        return Err("snapshot size must be greater than zero".to_string());
    }
    let name = snapshot_name(&volume, requested_name)?;
    let path = snapshot_path(&volume, &name)?;

    if path.exists() {
        return Err(format!(
            "[{}] snapshot already exists: {}",
            volume.id,
            path.display()
        ));
    }

    run_command(
        "lvcreate",
        &[
            "--yes",
            "--snapshot",
            "--size",
            size,
            "--name",
            &name,
            &volume.lv,
        ],
    )?;
    println!("{}", path.display());
    Ok(())
}

pub fn run_snapshot_remove(
    state_file: &Path,
    volume_id: &str,
    requested_name: Option<&str>,
) -> Result<(), String> {
    let volume = load_volume(state_file, volume_id)?;
    let name = snapshot_name(&volume, requested_name)?;
    let path = snapshot_path(&volume, &name)?;

    if !path.exists() {
        return Err(format!(
            "[{}] snapshot does not exist: {}",
            volume.id,
            path.display()
        ));
    }
    if is_mounted(&path)? {
        return Err(format!(
            "[{}] refusing to remove mounted snapshot {}",
            volume.id,
            path.display()
        ));
    }

    let origin = command_output(
        "lvs",
        &[
            "--noheadings",
            "--options",
            "origin",
            path_string(&path)?.as_str(),
        ],
    )?;
    let expected_origin = lv_name(&volume)?;
    if origin.trim() != expected_origin {
        return Err(format!(
            "[{}] refusing to remove {}: expected origin {}, got {}",
            volume.id,
            path.display(),
            expected_origin,
            origin.trim()
        ));
    }

    run_command("lvremove", &["--yes", path_string(&path)?.as_str()])
}

pub fn run_snapshot_list(state_file: &Path, volume_ids: &[String]) -> Result<(), String> {
    let volumes = load_volumes(state_file, volume_ids)?;
    let mut rows = Vec::new();

    for volume in volumes {
        let output = command_output(
            "lvs",
            &[
                "--noheadings",
                "--separator",
                "|",
                "--options",
                "lv_name,origin,lv_size,data_percent",
                "--select",
                &format!("origin={}", lv_name(&volume)?),
            ],
        )?;
        for line in output.lines().filter(|line| !line.trim().is_empty()) {
            let fields = line
                .split('|')
                .map(|field| field.trim().to_string())
                .collect::<Vec<_>>();
            if fields.len() == 4 {
                rows.push(vec![
                    volume.id.clone(),
                    fields[0].clone(),
                    fields[2].clone(),
                    fields[3].clone(),
                ]);
            }
        }
    }

    print_table(&["volume", "snapshot", "size", "used"], &rows);
    Ok(())
}

fn snapshot_name(volume: &Volume, requested_name: Option<&str>) -> Result<String, String> {
    let name = requested_name.map(str::to_string).unwrap_or_else(|| {
        format!(
            "{}-snapshot",
            lv_name(volume).unwrap_or_else(|_| volume.id.clone())
        )
    });
    let valid = !name.is_empty()
        && name.len() <= 127
        && name.chars().all(|character| {
            character.is_ascii_lowercase() || character.is_ascii_digit() || character == '-'
        });
    if valid {
        Ok(name)
    } else {
        Err(format!("invalid snapshot LV name {name:?}"))
    }
}

fn snapshot_path(volume: &Volume, name: &str) -> Result<PathBuf, String> {
    let parent = Path::new(&volume.lv)
        .parent()
        .ok_or_else(|| format!("[{}] invalid LV path {}", volume.id, volume.lv))?;
    Ok(parent.join(name))
}

fn lv_name(volume: &Volume) -> Result<String, String> {
    Path::new(&volume.lv)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .ok_or_else(|| format!("[{}] invalid LV path {}", volume.id, volume.lv))
}

fn is_mounted(path: &Path) -> Result<bool, String> {
    let path = path_string(path)?;
    let output = Command::new("findmnt")
        .args(["--noheadings", "--source", &path])
        .output()
        .map_err(|error| format!("failed to run findmnt: {error}"))?;
    match output.status.code() {
        Some(0) => Ok(true),
        Some(1) => Ok(false),
        status => Err(command_error("findmnt", status, &output)),
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
        Err(command_error(program, output.status.code(), &output))
    }
}

fn command_output(program: &str, args: &[&str]) -> Result<String, String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| format!("failed to run {program}: {error}"))?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        Err(command_error(program, output.status.code(), &output))
    }
}

fn command_error(program: &str, status: Option<i32>, output: &Output) -> String {
    let stderr = String::from_utf8_lossy(&output.stderr);
    format!(
        "{program} failed with status {}: {}",
        status.map_or_else(|| "signal".to_string(), |code| code.to_string()),
        if stderr.trim().is_empty() {
            "no error output"
        } else {
            stderr.trim()
        }
    )
}

fn path_string(path: &Path) -> Result<String, String> {
    path.to_str()
        .map(str::to_string)
        .ok_or_else(|| format!("path is not valid UTF-8: {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::snapshot_name;
    use crate::models::Volume;

    fn volume() -> Volume {
        Volume {
            id: "data".to_string(),
            lv: "/dev/pool/data".to_string(),
            size: "1G".to_string(),
            fs_type: "ext4".to_string(),
            uuid: "uuid".to_string(),
        }
    }

    #[test]
    fn generates_snapshot_name() {
        assert_eq!(snapshot_name(&volume(), None).unwrap(), "data-snapshot");
    }

    #[test]
    fn rejects_unsafe_snapshot_name() {
        assert!(snapshot_name(&volume(), Some("../data")).is_err());
        assert!(snapshot_name(&volume(), Some("DATA")).is_err());
    }
}
