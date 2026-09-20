use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    os::fd::AsRawFd,
    path::Path,
    thread,
    time::{Duration, Instant},
};

use crate::models::Volume;

const LOCK_ROOT: &str = "/run/lock/homelab-volume";

pub struct VolumeLocks {
    _files: Vec<File>,
}

impl VolumeLocks {
    pub fn acquire(volumes: &[Volume], operation: &str) -> Result<Self, String> {
        let mut ids = Vec::with_capacity(volumes.len());
        for volume in volumes {
            ids.push(volume.id.clone());
        }
        Self::acquire_ids(&ids, operation, Duration::ZERO)
    }

    /// Lock arbitrary identifiers, retrying until `wait` has elapsed. Volume
    /// IDs lock the volume; other names (such as `owner@<service>`) are
    /// coordination locks that cannot collide with a volume ID.
    pub fn acquire_ids(ids: &[String], operation: &str, wait: Duration) -> Result<Self, String> {
        fs::create_dir_all(LOCK_ROOT)
            .map_err(|error| format!("failed to create {LOCK_ROOT}: {error}"))?;

        let deadline = Instant::now() + wait;
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
            loop {
                let result =
                    unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
                if result == 0 {
                    break;
                }
                if Instant::now() >= deadline {
                    return Err(format!(
                        "{id:?} is already locked by another operation: {}",
                        path.display()
                    ));
                }
                thread::sleep(Duration::from_secs(1));
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
