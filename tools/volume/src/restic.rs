use crate::models::BackupTarget;
use serde::Deserialize;
use std::fs;
use std::process::{Command, Output};

#[derive(Clone, Debug, Deserialize)]
pub struct ResticSnapshot {
    pub id: String,
    pub time: String,
    pub hostname: String,
    #[serde(default)]
    pub tags: Vec<String>,
}

pub fn command(target: &BackupTarget) -> Result<Command, String> {
    let mut command = Command::new("restic");
    command.args(["--repository", &target.repository]);
    if let Some(password_file) = &target.password_file {
        command.args(["--password-file", password_file]);
    }
    if let Some(environment_file) = &target.environment_file {
        for (name, value) in parse_environment_file(environment_file)? {
            command.env(name, value);
        }
    }
    Ok(command)
}

pub fn snapshots(
    target: &BackupTarget,
    required_tags: &[String],
    source_host: Option<&str>,
) -> Result<Vec<ResticSnapshot>, String> {
    let mut command = command(target)?;
    command.args(["snapshots", "--json"]);
    if !required_tags.is_empty() {
        command.args(["--tag", &required_tags.join(",")]);
    }
    if let Some(host) = source_host {
        command.args(["--host", host]);
    }
    let output = run_output(&mut command)?;
    serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("failed to parse restic snapshot list: {error}"))
}

pub fn ensure_repository(target: &BackupTarget) -> Result<(), String> {
    let mut probe = command(target)?;
    probe.args(["snapshots", "--json", "--latest", "1"]);
    match run_output(&mut probe) {
        Ok(_) => Ok(()),
        Err(probe_error) if target.initialize => {
            let mut initialize = command(target)?;
            initialize.arg("init");
            run(&mut initialize).map_err(|initialize_error| {
                format!(
                    "Restic repository probe failed: {probe_error}\nrepository initialization also failed: {initialize_error}"
                )
            })
        }
        Err(error) => Err(error),
    }
}

pub fn run(command: &mut Command) -> Result<(), String> {
    let status = command
        .status()
        .map_err(|error| format!("failed to execute restic: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("restic failed with {status}"))
    }
}

fn run_output(command: &mut Command) -> Result<Output, String> {
    let output = command
        .output()
        .map_err(|error| format!("failed to execute restic: {error}"))?;
    if output.status.success() {
        Ok(output)
    } else {
        Err(format!(
            "restic failed with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        ))
    }
}

fn parse_environment_file(path: &str) -> Result<Vec<(String, String)>, String> {
    let contents = fs::read_to_string(path)
        .map_err(|error| format!("failed to read Restic environment file {path}: {error}"))?;
    let mut values = Vec::new();
    for (index, original) in contents.lines().enumerate() {
        let line = original.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (name, raw_value) = line
            .split_once('=')
            .ok_or_else(|| format!("invalid assignment in {path}:{}", index + 1))?;
        let name = name.trim();
        if name.is_empty()
            || !name
                .chars()
                .all(|character| character.is_ascii_alphanumeric() || character == '_')
        {
            return Err(format!("invalid variable name in {path}:{}", index + 1));
        }
        let raw_value = raw_value.trim();
        let value = if raw_value.len() >= 2
            && ((raw_value.starts_with('"') && raw_value.ends_with('"'))
                || (raw_value.starts_with('\'') && raw_value.ends_with('\'')))
        {
            raw_value[1..raw_value.len() - 1].to_string()
        } else {
            raw_value.to_string()
        };
        values.push((name.to_string(), value));
    }
    Ok(values)
}

#[cfg(test)]
mod tests {
    use super::parse_environment_file;
    use std::fs;

    #[test]
    fn parses_restic_environment_file() {
        let path = std::env::temp_dir().join(format!("volume-env-{}", std::process::id()));
        fs::write(
            &path,
            "# comment\nAWS_ACCESS_KEY_ID=abc\nAWS_SECRET_ACCESS_KEY='hello world'\n",
        )
        .unwrap();
        let values = parse_environment_file(path.to_str().unwrap()).unwrap();
        fs::remove_file(path).unwrap();
        assert_eq!(
            values,
            vec![
                ("AWS_ACCESS_KEY_ID".to_string(), "abc".to_string()),
                (
                    "AWS_SECRET_ACCESS_KEY".to_string(),
                    "hello world".to_string()
                )
            ]
        );
    }
}
