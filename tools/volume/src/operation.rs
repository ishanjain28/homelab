use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const OPERATION_ROOT: &str = "/var/lib/homelab-volume/operations";

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Operation {
    pub schema_version: u32,
    pub id: String,
    pub kind: String,
    pub phase: String,
    pub owner_service: String,
    #[serde(default)]
    pub owner_was_active: bool,
    pub source_host: Option<String>,
    pub snapshot_id: Option<String>,
    pub target: String,
    pub volumes: Vec<OperationVolume>,
    #[serde(default)]
    pub completed_volumes: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationVolume {
    pub id: String,
    pub active_name: String,
    pub uuid: String,
    pub fs_type: String,
    pub staging_name: String,
    pub rollback_name: String,
    pub failed_name: String,
    #[serde(default)]
    pub had_active: bool,
}

impl Operation {
    pub fn save(&self) -> Result<(), String> {
        fs::create_dir_all(OPERATION_ROOT)
            .map_err(|error| format!("failed to create {OPERATION_ROOT}: {error}"))?;
        let path = operation_path(&self.id)?;
        let temporary = path.with_extension("json.new");
        let contents = serde_json::to_vec_pretty(self)
            .map_err(|error| format!("failed to serialize operation {}: {error}", self.id))?;
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(&temporary)
            .map_err(|error| format!("failed to open {}: {error}", temporary.display()))?;
        file.write_all(&contents)
            .map_err(|error| format!("failed to write {}: {error}", temporary.display()))?;
        file.sync_all()
            .map_err(|error| format!("failed to sync {}: {error}", temporary.display()))?;
        fs::rename(&temporary, &path).map_err(|error| {
            format!(
                "failed to commit operation journal {}: {error}",
                path.display()
            )
        })?;
        sync_directory(Path::new(OPERATION_ROOT))
    }
}

pub fn load_operation(id: &str) -> Result<Operation, String> {
    let path = operation_path(id)?;
    let contents = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    parse_operation(&contents, &path)
}

pub fn list_operations() -> Result<Vec<Operation>, String> {
    let directory = Path::new(OPERATION_ROOT);
    if !directory.exists() {
        return Ok(Vec::new());
    }
    let mut operations = Vec::new();
    for entry in fs::read_dir(directory)
        .map_err(|error| format!("failed to read {OPERATION_ROOT}: {error}"))?
    {
        let entry = entry.map_err(|error| format!("failed to read operation entry: {error}"))?;
        if entry.path().extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let contents = fs::read_to_string(entry.path())
            .map_err(|error| format!("failed to read {}: {error}", entry.path().display()))?;
        operations.push(parse_operation(&contents, &entry.path())?);
    }
    Ok(operations)
}

fn parse_operation(contents: &str, path: &Path) -> Result<Operation, String> {
    let operation = serde_json::from_str::<Operation>(contents)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    if operation.schema_version != 1 {
        return Err(format!(
            "unsupported operation schema {} in {}",
            operation.schema_version,
            path.display()
        ));
    }
    Ok(operation)
}

pub fn new_operation_id(prefix: &str) -> Result<String, String> {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("system clock is before the Unix epoch: {error}"))?;
    Ok(format!(
        "{prefix}-{}-{}-{}",
        duration.as_secs(),
        duration.subsec_millis(),
        std::process::id()
    ))
}

fn operation_path(id: &str) -> Result<PathBuf, String> {
    if id.is_empty()
        || !id
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || character == '-')
    {
        return Err(format!("invalid operation id {id:?}"));
    }
    Ok(Path::new(OPERATION_ROOT).join(format!("{id}.json")))
}

fn sync_directory(path: &Path) -> Result<(), String> {
    let directory = fs::File::open(path)
        .map_err(|error| format!("failed to open {} for sync: {error}", path.display()))?;
    directory
        .sync_all()
        .map_err(|error| format!("failed to sync {}: {error}", path.display()))
}
