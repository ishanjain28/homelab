#[derive(Clone, Debug)]
pub struct Volume {
    pub id: String,
    pub lv: String,
    pub path: String,
    pub size: String,
    pub fs_type: String,
    pub uuid: String,
    pub host_uid: String,
    pub host_gid: String,
    pub mode: String,
    pub owner_service: String,
}

#[derive(Clone)]
pub struct ActualVolume {
    pub host: String,
    pub uuid: String,
    pub lv: String,
    pub fs_type: String,
    pub size_bytes: String,
    pub mountpoint: String,
}

pub struct Context {
    pub flake: String,
    pub ssh_config: String,
}

