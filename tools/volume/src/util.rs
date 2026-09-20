use core::convert::AsRef;
use dialoguer::Confirm;
use std::{
    fs::{self, File},
    io,
    os::{fd::AsRawFd, unix::fs::FileTypeExt},
    path::Path,
    process::{Command, Output},
};

pub fn confirm(assume_yes: bool, prompt: &str) -> Result<bool, String> {
    if assume_yes {
        return Ok(true);
    }

    Confirm::new()
        .with_prompt(prompt)
        .default(false)
        .interact()
        .map_err(|error| format!("failed to read confirmation: {error}"))
}

pub fn parse_size(value: &str) -> Result<u64, String> {
    let value = value.trim();
    let split_at = value
        .find(|character: char| !character.is_ascii_digit())
        .unwrap_or(value.len());
    let number = value[..split_at]
        .parse::<u64>()
        .map_err(|error| format!("invalid size {value:?}: {error}"))?;
    let suffix = value[split_at..]
        .trim()
        .trim_end_matches('B')
        .to_ascii_uppercase();
    let multiplier = match suffix.as_str() {
        "" => 1,
        "K" | "KI" => 1024,
        "M" | "MI" => 1024_u64.pow(2),
        "G" | "GI" => 1024_u64.pow(3),
        "T" | "TI" => 1024_u64.pow(4),
        "P" | "PI" => 1024_u64.pow(5),
        unsupported => {
            return Err(format!(
                "unsupported size suffix {unsupported:?} in {value:?}"
            ))
        }
    };

    number
        .checked_mul(multiplier)
        .ok_or_else(|| format!("size is too large: {value:?}"))
}

pub fn parse_blkid_output(output: Output) -> Result<Vec<(String, String)>, String> {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let status_code = output.status.code();

    if status_code == Some(0) {
        let mut data = vec![];
        for line in stdout.lines() {
            let Some((k, v)) = line.split_once(|x| x == '=') else {
                return Err(format!("failed to parse blkid output={line}"));
            };

            data.push((k.to_owned(), v.to_owned()));
        }

        return Ok(data);
    }

    if status_code == Some(2) && stdout.trim().is_empty() && stderr.trim().is_empty() {
        return Ok(vec![]);
    }

    Err(format!(
        "blkid (status {}): {}",
        status_code.map_or_else(|| "signal".to_string(), |code| code.to_string()),
        if stderr.trim().is_empty() {
            "no error output"
        } else {
            stderr.trim()
        }
    ))
}

pub fn block_device_size(path: impl AsRef<Path>) -> Result<u64, String> {
    let path = path.as_ref();
    const BLKGETSIZE64: libc::c_ulong = 0x8008_1272;

    let file =
        File::open(path).map_err(|error| format!("failed to open {}: {error}", path.display()))?;
    let mut size = 0_u64;
    let result = unsafe { libc::ioctl(file.as_raw_fd(), BLKGETSIZE64, &mut size) };
    if result == 0 {
        Ok(size)
    } else {
        Err(format!(
            "failed to get block size for {}: {}",
            path.display(),
            io::Error::last_os_error()
        ))
    }
}

pub fn is_block_device(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| metadata.file_type().is_block_device())
        .unwrap_or(false)
}

pub fn is_mounted(device: &str) -> Result<bool, String> {
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

pub fn is_mountpoint(path: &Path) -> Result<bool, String> {
    let output = Command::new("findmnt")
        .args(["--noheadings", "--mountpoint"])
        .arg(path)
        .output()
        .map_err(|error| format!("failed to run findmnt: {error}"))?;

    match output.status.code() {
        Some(0) => Ok(true),
        Some(1) => Ok(false),
        status => Err(format!(
            "findmnt failed while checking {} (status {}): {}",
            path.display(),
            status.map_or_else(|| "signal".to_string(), |code| code.to_string()),
            String::from_utf8_lossy(&output.stderr).trim()
        )),
    }
}

pub fn run_command(program: &str, args: &[&str]) -> Result<(), String> {
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

pub fn command_output(output: &std::process::Output) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    [stdout.trim(), stderr.trim()]
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}
