use anyhow::{ensure, Context, Result};
use std::process::Command;

use crate::util::{command_stdout, run_command};

/// Freezes the owner unit's cgroup for the duration of a snapshot. Dropping
/// the guard without calling `release` thaws it, so an early error cannot
/// leave a container frozen. An inactive unit is left alone.
pub struct QuiesceGuard {
    unit: String,
    frozen: bool,
}

impl QuiesceGuard {
    pub fn begin(unit: &str) -> Result<Self> {
        let mut guard = Self {
            unit: unit.to_string(),
            frozen: false,
        };
        if !unit_is_active(unit)? {
            return Ok(guard);
        }
        let state = freezer_state(unit)?;
        ensure!(
            state == "running",
            "refusing to freeze {unit}: freezer state is {state:?}"
        );
        run_command("systemctl", &["freeze", unit])?;
        log::info!(unit = unit; "frozen");
        guard.frozen = true;
        Ok(guard)
    }

    pub fn release(mut self) -> Result<()> {
        thaw_if_frozen(&self.unit)?;
        self.frozen = false;
        Ok(())
    }
}

impl Drop for QuiesceGuard {
    fn drop(&mut self) {
        if self.frozen {
            if let Err(error) = thaw_if_frozen(&self.unit) {
                log::error!(unit = self.unit.as_str(); "failed to thaw owner: {error:#}");
            }
        }
    }
}

pub fn thaw_if_frozen(unit: &str) -> Result<()> {
    if freezer_state(unit)? == "frozen" {
        run_command("systemctl", &["thaw", unit])?;
        log::info!(unit = unit; "thawed");
    }
    Ok(())
}

fn unit_is_active(unit: &str) -> Result<bool> {
    let status = Command::new("systemctl")
        .args(["is-active", "--quiet", unit])
        .status()
        .context("failed to run systemctl is-active")?;
    Ok(status.success())
}

fn freezer_state(unit: &str) -> Result<String> {
    command_stdout(
        "systemctl",
        &["show", "--property", "FreezerState", "--value", unit],
    )
    .with_context(|| format!("failed to query freezer state of {unit}"))
}
