use std::process::Command;

use crate::util::run_command;

/// Freezes the owner unit's cgroup for the duration of a snapshot. Dropping
/// the guard without calling `release` thaws it, so an early error cannot
/// leave a container frozen. An inactive unit is left alone.
pub struct QuiesceGuard {
    unit: String,
    frozen: bool,
}

impl QuiesceGuard {
    pub fn begin(unit: &str) -> Result<Self, String> {
        let mut guard = Self {
            unit: unit.to_string(),
            frozen: false,
        };
        if !unit_is_active(unit)? {
            return Ok(guard);
        }
        let state = freezer_state(unit)?;
        if state != "running" {
            return Err(format!(
                "refusing to freeze {unit}: freezer state is {state:?}"
            ));
        }
        run_command("systemctl", &["freeze", unit])?;
        log::info!(unit = unit; "frozen");
        guard.frozen = true;
        Ok(guard)
    }

    pub fn release(mut self) -> Result<(), String> {
        thaw_if_frozen(&self.unit)?;
        self.frozen = false;
        Ok(())
    }
}

impl Drop for QuiesceGuard {
    fn drop(&mut self) {
        if self.frozen {
            if let Err(error) = thaw_if_frozen(&self.unit) {
                log::error!(unit = self.unit.as_str(); "failed to thaw owner: {error}");
            }
        }
    }
}

pub fn thaw_if_frozen(unit: &str) -> Result<(), String> {
    if freezer_state(unit)? == "frozen" {
        run_command("systemctl", &["thaw", unit])?;
        log::info!(unit = unit; "thawed");
    }
    Ok(())
}

fn unit_is_active(unit: &str) -> Result<bool, String> {
    let status = Command::new("systemctl")
        .args(["is-active", "--quiet", unit])
        .status()
        .map_err(|error| format!("failed to run systemctl is-active: {error}"))?;
    Ok(status.success())
}

fn freezer_state(unit: &str) -> Result<String, String> {
    let output = Command::new("systemctl")
        .args(["show", "--property", "FreezerState", "--value", unit])
        .output()
        .map_err(|error| format!("failed to query freezer state of {unit}: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "systemctl show failed for {unit}: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}
