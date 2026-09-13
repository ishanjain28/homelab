use core::convert::AsRef;
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    os::fd::AsRawFd,
    path::Path,
};

use crate::models::Volume;

const LOCK_ROOT: &str = "/run/lock/homelab-volume";

pub struct VolumeLocks {
    _files: Vec<File>,
}

impl VolumeLocks {
    pub fn acquire(volumes: &[Volume], operation: &str) -> Result<Self, String> {
        fs::create_dir_all(LOCK_ROOT)
            .map_err(|error| format!("failed to create {LOCK_ROOT}: {error}"))?;

        let mut files = Vec::with_capacity(volumes.len());

        for volume in volumes.as_ref() {
            let id = &volume.id;

            let path = Path::new(LOCK_ROOT).join(format!("{id}.lock"));
            let mut file = OpenOptions::new()
                .create(true)
                .truncate(false)
                .read(true)
                .write(true)
                .open(&path)
                .map_err(|error| format!("failed to open {}: {error}", path.display()))?;
            let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
            if result != 0 {
                return Err(format!(
                    "volume {id:?} is already locked by another operation: {}",
                    path.display()
                ));
            }
            file.set_len(0)
                .map_err(|error| format!("failed to truncate {}: {error}", path.display()))?;
            writeln!(file, "pid={} operation={operation}", std::process::id())
                .map_err(|error| format!("failed to write {}: {error}", path.display()))?;
            files.push(file);
        }

        Ok(Self { _files: files })
    }
}
