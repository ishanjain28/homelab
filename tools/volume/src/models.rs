use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct State {
    pub schema_version: u32,
    pub host: String,
    pub volumes: BTreeMap<String, Volume>,
    #[serde(default)]
    pub backup_targets: BTreeMap<String, BackupTarget>,
    #[serde(default)]
    pub deleted_volumes: BTreeMap<String, DeletedVolume>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Volume {
    pub id: String,
    pub lv: String,
    pub name: String,
    pub size: String,
    pub fs_type: String,
    pub uuid: String,
    pub owner_service: String,
    pub owner_enabled: bool,
    pub owner_unit: String,
    pub host_mount_path: String,
    pub mount_path: String,
    pub mode: String,
    #[serde(default)]
    pub backup: Option<BackupPolicy>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BackupPolicy {
    pub target: String,
    pub cron: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupTarget {
    pub repository: String,
    pub password_file: Option<String>,
    pub environment_file: Option<String>,
    #[serde(default)]
    pub initialize: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeletedVolume {
    pub name: String,
    pub uuid: String,
    pub after: String,
    pub reason: String,
}

pub fn load_state(state_file: &Path) -> Result<State, String> {
    let contents = fs::read_to_string(state_file)
        .map_err(|error| format!("failed to read {}: {error}", state_file.display()))?;
    let state = serde_json::from_str::<State>(&contents)
        .map_err(|error| format!("failed to parse {}: {error}", state_file.display()))?;

    if state.schema_version != 1 {
        return Err(format!(
            "unsupported volume state schema {} in {}",
            state.schema_version,
            state_file.display()
        ));
    }

    for (key, volume) in &state.volumes {
        if !is_safe_identifier(key) {
            return Err(format!(
                "invalid volume id {key:?} in {}",
                state_file.display()
            ));
        }
        if key != &volume.id {
            return Err(format!(
                "volume state key {key:?} does not match volume id {:?}",
                volume.id
            ));
        }
    }

    Ok(state)
}

fn is_safe_identifier(value: &str) -> bool {
    !value.is_empty()
        && value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_'))
}

pub fn load_volumes(state_file: &Path, volume_ids: &[String]) -> Result<Vec<Volume>, String> {
    let state = load_state(state_file)?;

    if volume_ids.is_empty() {
        return Ok(state.volumes.into_values().collect());
    }

    volume_ids
        .iter()
        .map(|id| {
            state
                .volumes
                .get(id)
                .cloned()
                .ok_or_else(|| format!("volume {id:?} is not declared in {}", state_file.display()))
        })
        .collect()
}

pub fn load_volume(state_file: &Path, volume_id: &str) -> Result<Volume, String> {
    load_volumes(state_file, &[volume_id.to_string()])?
        .into_iter()
        .next()
        .ok_or_else(|| {
            format!(
                "volume {volume_id:?} is not declared in {}",
                state_file.display()
            )
        })
}
