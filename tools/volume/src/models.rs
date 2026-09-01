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
    #[serde(rename = "hostPath")]
    pub path: String,
    pub size: String,
    #[serde(rename = "fsType")]
    pub fs_type: String,
    pub uuid: String,
    #[serde(rename = "owner")]
    pub owner: VolumeOwner,
}

#[derive(Clone, Debug, Deserialize)]
pub struct VolumeOwner {
    #[serde(rename = "hostUid")]
    pub host_uid: u32,
    #[serde(rename = "hostGid")]
    pub host_gid: u32,
    pub mode: String,
}

#[allow(dead_code)]
#[derive(Clone)]
pub struct ActualVolume {
    pub host: String,
    pub uuid: String,
    pub lv: String,
    pub fs_type: String,
    pub size_bytes: String,
    pub mountpoint: String,
}

#[allow(dead_code)]
pub struct Context {
    pub flake: String,
    pub ssh_config: String,
}
