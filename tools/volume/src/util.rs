use anyhow::{bail, ensure, Context, Result};
use dialoguer::Confirm;
use std::{
    fs::{self, File},
    io,
    os::{fd::AsRawFd, unix::fs::FileTypeExt},
    path::Path,
    process::{Command, Output},
    sync::atomic::{AtomicBool, Ordering},
};

static INTERRUPTED: AtomicBool = AtomicBool::new(false);

extern "C" fn on_interrupt(_signal: libc::c_int) {
    INTERRUPTED.store(true, Ordering::SeqCst);
}

/// Turn SIGINT, SIGTERM and SIGHUP into a flag, so long transfers can stop and clean up their
/// temporary LVs. The handler is installed without SA_RESTART so blocked reads return EINTR.
pub fn install_interrupt_handler() {
    for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP] {
        // SAFETY: the handler only stores to an atomic, which is async-signal-safe.
        unsafe {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = on_interrupt as extern "C" fn(libc::c_int) as usize;
            libc::sigemptyset(&mut action.sa_mask);
            libc::sigaction(signal, &action, std::ptr::null_mut());
        }
    }
}

pub fn interrupted() -> bool {
    INTERRUPTED.load(Ordering::SeqCst)
}

pub fn confirm(assume_yes: bool, prompt: &str) -> Result<bool> {
    if assume_yes {
        return Ok(true);
    }

    Confirm::new()
        .with_prompt(prompt)
        .default(false)
        .interact()
        .context("failed to read confirmation")
}

pub fn parse_size(value: &str) -> Result<u64> {
    let value = value.trim();
    let split_at = value
        .find(|character: char| !character.is_ascii_digit())
        .unwrap_or(value.len());
    let number = value[..split_at]
        .parse::<u64>()
        .with_context(|| format!("invalid size {value:?}"))?;
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
        unsupported => bail!("unsupported size suffix {unsupported:?} in {value:?}"),
    };

    number
        .checked_mul(multiplier)
        .with_context(|| format!("size is too large: {value:?}"))
}

pub fn parse_blkid_output(output: Output) -> Result<Vec<(String, String)>> {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let status_code = output.status.code();

    if status_code == Some(0) {
        let mut data = vec![];
        for line in stdout.lines() {
            let Some((k, v)) = line.split_once('=') else {
                bail!("failed to parse blkid output={line}");
            };

            data.push((k.to_owned(), v.to_owned()));
        }

        return Ok(data);
    }

    if status_code == Some(2) && stdout.trim().is_empty() && stderr.trim().is_empty() {
        return Ok(vec![]);
    }

    bail!(
        "blkid (status {}): {}",
        status_code.map_or_else(|| "signal".to_string(), |code| code.to_string()),
        if stderr.trim().is_empty() {
            "no error output"
        } else {
            stderr.trim()
        }
    )
}

pub fn block_device_size(path: impl AsRef<Path>) -> Result<u64> {
    let path = path.as_ref();
    const BLKGETSIZE64: libc::c_ulong = 0x8008_1272;

    let file = File::open(path).with_context(|| format!("failed to open {}", path.display()))?;
    let mut size = 0_u64;
    let result = unsafe { libc::ioctl(file.as_raw_fd(), BLKGETSIZE64, &mut size) };
    ensure!(
        result == 0,
        "failed to get block size for {}: {}",
        path.display(),
        io::Error::last_os_error()
    );
    Ok(size)
}

pub fn is_block_device(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| metadata.file_type().is_block_device())
        .unwrap_or(false)
}

/// Whether `device` is the source of any mount.
pub fn is_mounted(device: &str) -> Result<bool> {
    findmnt(&["--noheadings", "--source", device])
}

/// Whether `path` is a mount point.
pub fn is_mountpoint(path: &Path) -> Result<bool> {
    findmnt(&["--noheadings", "--mountpoint", &path.to_string_lossy()])
}

fn findmnt(args: &[&str]) -> Result<bool> {
    let output = Command::new("findmnt")
        .args(args)
        .output()
        .context("failed to run findmnt")?;
    match output.status.code() {
        Some(0) => Ok(true),
        Some(1) => Ok(false),
        _ => bail!("findmnt {}: {}", args.join(" "), command_output(&output)),
    }
}

/// Run a command, failing with its combined output when it exits non-zero.
pub fn run_command(program: &str, args: &[&str]) -> Result<()> {
    command_stdout(program, args).map(drop)
}

/// Run a command and return its trimmed stdout, failing with its combined
/// output when it exits non-zero.
pub fn command_stdout(program: &str, args: &[&str]) -> Result<String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .with_context(|| format!("failed to run {program}"))?;
    ensure!(
        output.status.success(),
        "{program} {} failed: {}",
        args.join(" "),
        command_output(&output)
    );
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

pub fn command_output(output: &Output) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    [stdout.trim(), stderr.trim()]
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}
