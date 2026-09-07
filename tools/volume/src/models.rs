use serde::Deserialize;

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
