use crate::models::{ActualVolume, Context, Volume};
use crate::nix::{actual_volumes, hosts, volumes};
use crate::table::print_table;
use std::collections::HashMap;

struct MigrationRow {
    uuid: String,
    volume: String,
    desired_host: String,
    actual_hosts: String,
    status: String,
    detail: String,
}

pub fn run_migrate(context: &Context, requested_hosts: &[String]) -> Result<(), String> {
    let host_names = hosts(context, requested_hosts)?;
    let mut desired_by_uuid: HashMap<String, Vec<(String, Volume)>> = HashMap::new();
    let mut actual_by_uuid: HashMap<String, Vec<ActualVolume>> = HashMap::new();

    for host in &host_names {
        for volume in volumes(context, host)? {
            desired_by_uuid
                .entry(volume.uuid.clone())
                .or_default()
                .push((host.clone(), volume));
        }

        for volume in actual_volumes(context, host)? {
            actual_by_uuid.entry(volume.uuid.clone()).or_default().push(volume);
        }
    }

    let mut rows = Vec::new();
    let mut desired_uuids = desired_by_uuid.keys().cloned().collect::<Vec<_>>();
    desired_uuids.sort();

    for uuid in desired_uuids {
        let desired = &desired_by_uuid[&uuid];
        let actual = actual_by_uuid.get(&uuid).cloned().unwrap_or_default();

        if desired.len() > 1 {
            rows.push(MigrationRow {
                uuid: uuid.clone(),
                volume: desired
                    .iter()
                    .map(|(_, volume)| volume.id.clone())
                    .collect::<Vec<_>>()
                    .join(","),
                desired_host: desired
                    .iter()
                    .map(|(host, _)| host.clone())
                    .collect::<Vec<_>>()
                    .join(","),
                actual_hosts: format_actual_hosts(&actual),
                status: "config-duplicate".to_string(),
                detail: "same UUID is declared more than once".to_string(),
            });
            continue;
        }

        let (desired_host, desired_volume) = &desired[0];
        if actual.is_empty() {
            rows.push(MigrationRow {
                uuid: uuid.clone(),
                volume: desired_volume.id.clone(),
                desired_host: desired_host.clone(),
                actual_hosts: "-".to_string(),
                status: "missing".to_string(),
                detail: "configured volume UUID was not found on scanned hosts".to_string(),
            });
            continue;
        }

        if actual.len() > 1 {
            rows.push(MigrationRow {
                uuid: uuid.clone(),
                volume: desired_volume.id.clone(),
                desired_host: desired_host.clone(),
                actual_hosts: format_actual_hosts(&actual),
                status: "actual-duplicate".to_string(),
                detail: "same UUID exists on more than one scanned host".to_string(),
            });
            continue;
        }

        let actual_volume = &actual[0];
        if &actual_volume.host == desired_host {
            rows.push(MigrationRow {
                uuid,
                volume: desired_volume.id.clone(),
                desired_host: desired_host.clone(),
                actual_hosts: actual_volume.summary(),
                status: "ok".to_string(),
                detail: "volume is on the configured host".to_string(),
            });
        } else {
            rows.push(MigrationRow {
                uuid,
                volume: desired_volume.id.clone(),
                desired_host: desired_host.clone(),
                actual_hosts: actual_volume.summary(),
                status: "migrate".to_string(),
                detail: format!("move from {} to {}", actual_volume.host, desired_host),
            });
        }
    }

    let mut actual_uuids = actual_by_uuid.keys().cloned().collect::<Vec<_>>();
    actual_uuids.sort();
    for uuid in actual_uuids {
        if desired_by_uuid.contains_key(&uuid) {
            continue;
        }

        let actual = &actual_by_uuid[&uuid];
        rows.push(MigrationRow {
            uuid,
            volume: "-".to_string(),
            desired_host: "-".to_string(),
            actual_hosts: format_actual_hosts(actual),
            status: "unmanaged".to_string(),
            detail: "actual LVM volume UUID is not declared in config".to_string(),
        });
    }

    print_migration_table(&rows);
    if rows.iter().any(|row| row.status != "ok") {
        Err("one or more volumes need attention".to_string())
    } else {
        Ok(())
    }
}

fn print_migration_table(rows: &[MigrationRow]) {
    let headers = ["uuid", "volume", "desired", "actual", "status", "detail"];
    let rows = rows.iter().map(MigrationRow::fields).collect::<Vec<_>>();
    print_table(&headers, &rows);
}

impl MigrationRow {
    fn fields(&self) -> Vec<String> {
        vec![
            self.uuid.clone(),
            self.volume.clone(),
            self.desired_host.clone(),
            self.actual_hosts.clone(),
            self.status.clone(),
            self.detail.clone(),
        ]
    }
}

impl ActualVolume {
    fn summary(&self) -> String {
        let mountpoint = if self.mountpoint.is_empty() {
            "unmounted"
        } else {
            &self.mountpoint
        };
        format!(
            "{}:{} {} {} {}",
            self.host, self.lv, self.fs_type, self.size_bytes, mountpoint
        )
    }
}

fn format_actual_hosts(volumes: &[ActualVolume]) -> String {
    if volumes.is_empty() {
        "-".to_string()
    } else {
        volumes
            .iter()
            .map(ActualVolume::summary)
            .collect::<Vec<_>>()
            .join("; ")
    }
}
