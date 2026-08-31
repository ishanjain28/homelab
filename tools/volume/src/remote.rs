use crate::models::Context;
use std::io::Write;
use std::process::{Command, Output, Stdio};

pub fn remote(context: &Context, host: &str, args: &[&str]) -> Result<String, String> {
    let output = Command::new("ssh")
        .args(["-n", "-F", &context.ssh_config, host, "sudo"])
        .args(args)
        .output()
        .map_err(|error| format!("failed to run ssh for {host}: {error}"))?;

    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }

    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub fn remote_status(context: &Context, host: &str, args: &[&str]) -> Result<bool, String> {
    let status = Command::new("ssh")
        .args(["-n", "-F", &context.ssh_config, host, "sudo"])
        .args(args)
        .status()
        .map_err(|error| format!("failed to run ssh for {host}: {error}"))?;
    Ok(status.success())
}

pub fn remote_script(context: &Context, host: &str, script: &str, args: &[&str]) -> Result<String, String> {
    let output = remote_script_raw(context, host, script, args)?;
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    print!("{stdout}");
    std::io::stdout().flush().ok();

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            Err(format!("remote command failed on {host}"))
        } else {
            Err(stderr)
        }
    } else {
        Ok(stdout)
    }
}

pub fn remote_script_raw(
    context: &Context,
    host: &str,
    script: &str,
    args: &[&str],
) -> Result<Output, String> {
    let mut child = Command::new("ssh")
        .args(["-F", &context.ssh_config, host, "sudo", "bash", "-s", "--"])
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to run ssh script for {host}: {error}"))?;

    child
        .stdin
        .as_mut()
        .ok_or_else(|| "failed to open ssh stdin".to_string())?
        .write_all(script.as_bytes())
        .map_err(|error| format!("failed to write ssh script: {error}"))?;

    child
        .wait_with_output()
        .map_err(|error| format!("failed to wait for ssh script: {error}"))
}
