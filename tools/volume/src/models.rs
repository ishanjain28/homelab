use anyhow::{ensure, Context, Result};
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
    #[serde(default)]
    pub backup: BackupPolicy,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupPolicy {
    #[serde(default)]
    pub groups: Vec<String>,
    #[serde(default = "default_snapshot_size")]
    pub snapshot_size: String,
}

impl Default for BackupPolicy {
    fn default() -> Self {
        Self {
            groups: Vec::new(),
            snapshot_size: default_snapshot_size(),
        }
    }
}

fn default_snapshot_size() -> String {
    "20%ORIGIN".to_string()
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeletedVolume {
    pub name: String,
    pub uuid: String,
    pub after: String,
    pub reason: String,
}

pub fn load_state(state_file: &Path) -> Result<State> {
    let contents = fs::read_to_string(state_file)
        .with_context(|| format!("failed to read {}", state_file.display()))?;
    let state = serde_json::from_str::<State>(&contents)
        .with_context(|| format!("failed to parse {}", state_file.display()))?;

    ensure!(
        state.schema_version == 1,
        "unsupported volume state schema {} in {}",
        state.schema_version,
        state_file.display()
    );

    for (key, volume) in &state.volumes {
        ensure!(
            is_safe_identifier(key),
            "invalid volume id {key:?} in {}",
            state_file.display()
        );
        ensure!(
            key == &volume.id,
            "volume state key {key:?} does not match volume id {:?}",
            volume.id
        );
        ensure!(
            is_safe_identifier(&volume.owner_service),
            "invalid owner service {:?} for volume {key:?}",
            volume.owner_service
        );
        for group in &volume.backup.groups {
            ensure!(
                is_safe_identifier(group),
                "invalid backup group {group:?} for volume {key:?}"
            );
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

pub fn load_volumes(state_file: &Path, volume_ids: &[String]) -> Result<Vec<Volume>> {
    let state = load_state(state_file)?;

    let mut volumes = Vec::with_capacity(volume_ids.len());
    for id in volume_ids {
        let volume = state.volumes.get(id).with_context(|| {
            format!("volume {id:?} is not declared in {}", state_file.display())
        })?;
        volumes.push(volume.clone());
    }
    Ok(volumes)
}

pub fn load_all_volumes(state_file: &Path) -> Result<Vec<Volume>> {
    let state = load_state(state_file)?;
    Ok(state.volumes.into_values().collect())
}

pub fn backup_volumes(state: &State, group: &str, owner_service: &str) -> Result<Vec<Volume>> {
    let mut volumes = Vec::new();
    for volume in state.volumes.values() {
        if volume.owner_service == owner_service && volume.backup.groups.iter().any(|g| g == group)
        {
            volumes.push(volume.clone());
        }
    }
    ensure!(
        !volumes.is_empty(),
        "service {owner_service:?} has no volumes in backup group {group:?}"
    );
    Ok(volumes)
}

pub fn service_volumes(state: &State, owner_service: &str) -> Result<Vec<Volume>> {
    let mut volumes = Vec::new();
    for volume in state.volumes.values() {
        if volume.owner_service == owner_service {
            volumes.push(volume.clone());
        }
    }
    ensure!(
        !volumes.is_empty(),
        "service {owner_service:?} owns no declared volumes"
    );
    Ok(volumes)
}
