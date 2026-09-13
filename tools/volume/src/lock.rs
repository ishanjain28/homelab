use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::fd::AsRawFd;
use std::path::Path;

const LOCK_ROOT: &str = "/run/lock/homelab-volume";

pub struct VolumeLocks {
    _files: Vec<File>,
}

impl VolumeLocks {
    pub fn acquire(volume_ids: &[String], operation: &str) -> Result<Self, String> {
        fs::create_dir_all(LOCK_ROOT)
            .map_err(|error| format!("failed to create {LOCK_ROOT}: {error}"))?;

        let mut ids = volume_ids.to_vec();
        ids.sort();
        ids.dedup();
        let mut files = Vec::with_capacity(ids.len());

        for id in ids {
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
