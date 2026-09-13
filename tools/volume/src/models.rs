use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, fs, path::Path};

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct State {
    pub schema_version: u32,
    pub host: String,
    pub volumes: BTreeMap<String, Volume>,
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
        if !is_safe_identifier(&volume.owner_service) {
            return Err(format!(
                "invalid owner service {:?} for volume {key:?}",
                volume.owner_service
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

pub fn load_all_volumes(state_file: &Path) -> Result<Vec<Volume>, String> {
    let state = load_state(state_file)?;

    return Ok(state.volumes.into_values().collect());
}

pub fn service_volumes(state: &State, owner_service: &str) -> Result<Vec<Volume>, String> {
    let volumes = state
        .volumes
        .values()
        .filter(|volume| volume.owner_service == owner_service)
        .cloned()
        .collect::<Vec<_>>();

    if volumes.is_empty() {
        Err(format!(
            "service {owner_service:?} owns no declared volumes"
        ))
    } else {
        Ok(volumes)
    }
}
