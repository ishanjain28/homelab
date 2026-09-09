use serde::Deserialize;
use std::fs;
use std::path::Path;

#[derive(Clone, Debug, Deserialize)]
pub struct VolumeSet {
    #[serde(flatten)]
    pub volumes: std::collections::BTreeMap<String, Volume>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct Volume {
    #[serde(rename = "volumeId")]
    pub id: String,
    #[serde(rename = "lvPath")]
    pub lv: String,
    pub size: String,
    #[serde(rename = "fsType")]
    pub fs_type: String,
    pub uuid: String,
}

pub fn load_volumes(state_file: &Path, volume_ids: &[String]) -> Result<Vec<Volume>, String> {
    let contents = fs::read_to_string(state_file)
        .map_err(|error| format!("failed to read {}: {error}", state_file.display()))?;
    let state = serde_json::from_str::<VolumeSet>(&contents)
        .map_err(|error| format!("failed to parse {}: {error}", state_file.display()))?;

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
