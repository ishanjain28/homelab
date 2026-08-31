use crate::models::{Context, Volume};
use crate::nix::{hosts, volumes};
use crate::remote::remote_script_raw;
use crate::table::{print_host_header, print_table};

struct CheckRow {
    volume: String,
    status: String,
    configured: String,
    allocated: String,
    used: String,
    lv: String,
    fs: String,
    uuid: String,
    mount: String,
    owner: String,
    mode: String,
}

pub fn run_check(context: &Context, requested_hosts: &[String]) -> Result<(), String> {
    let mut status = Ok(());
    for host in hosts(context, requested_hosts)? {
        print_host_header(&host);
        let declared = volumes(context, &host)?;
        if declared.is_empty() {
            println!("no homelab volumes declared for {host}");
            continue;
        }

        let mut rows = Vec::new();
        for volume in &declared {
            match check_volume(context, &host, volume) {
                Ok(row) => rows.push(row),
                Err(error) => {
                    eprintln!("{error}");
                    status = Err("one or more volume checks failed".to_string());
                }
            }
        }

        print_check_table(&rows);
        if rows.iter().any(|row| row.status != "ok") {
            status = Err("one or more volume checks failed".to_string());
        }
    }
    status
}

fn print_check_table(rows: &[CheckRow]) {
    let headers = [
        "volume",
        "status",
        "configured",
        "allocated",
        "used",
        "lv",
        "fs",
        "uuid",
        "mount",
        "owner",
        "mode",
    ];
    let rows = rows.iter().map(CheckRow::fields).collect::<Vec<_>>();
    print_table(&headers, &rows);
}

impl CheckRow {
    fn fields(&self) -> Vec<String> {
        vec![
            self.volume.clone(),
            self.status.clone(),
            self.configured.clone(),
            self.allocated.clone(),
            self.used.clone(),
            self.lv.clone(),
            self.fs.clone(),
            self.uuid.clone(),
            self.mount.clone(),
            self.owner.clone(),
            self.mode.clone(),
        ]
    }
}

fn check_volume(context: &Context, host: &str, volume: &Volume) -> Result<CheckRow, String> {
    let script = r#"
set -euo pipefail

id="$1"
lv="$2"
path="$3"
declared_size="$4"
expected_type="$5"
expected_uuid="$6"
expected_owner="$7:$8"
expected_mode="$(printf '%s' "$9" | sed 's/^0*//')"
expected_size="$(numfmt --from=iec "$declared_size")"
status=ok
allocated="-"
used="-"
lv_state=ok
fs_state=ok
uuid_state=ok
mount_state=ok
owner_state=ok
mode_state=ok

if [ ! -b "$lv" ]; then
  lv_state=missing
  fs_state=missing
  uuid_state=missing
  status=fail
else
  actual_size="$(blockdev --getsize64 "$lv")"
  allocated="$(numfmt --to=iec-i --suffix=B "$actual_size")"
  if [ "$actual_size" -gt "$expected_size" ]; then
    lv_state=large
    status=fail
  elif [ "$actual_size" -lt "$expected_size" ]; then
    lv_state=small
    status=fail
  fi

  actual_type="$(blkid -s TYPE -o value "$lv" 2>/dev/null || true)"
  if [ "$actual_type" != "$expected_type" ]; then
    fs_state="${actual_type:-missing}"
    status=fail
  fi

  actual_uuid="$(blkid -s UUID -o value "$lv" 2>/dev/null || true)"
  if [ "$actual_uuid" != "$expected_uuid" ]; then
    uuid_state="${actual_uuid:-missing}"
    status=fail
  fi
fi

if ! findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then
  mount_state=missing
  status=fail
else
  used="$(df -h --output=used "$path" 2>/dev/null | tail -n 1 | tr -d ' ' || printf '-')"
  expected_source="$(readlink -f "$lv" 2>/dev/null || true)"
  actual_source="$(findmnt -rn -o SOURCE --mountpoint "$path" 2>/dev/null || true)"
  actual_source="$(readlink -f "$actual_source" 2>/dev/null || true)"
  if [ "$actual_source" != "$expected_source" ]; then
    mount_state=source
    status=fail
  fi
fi

actual_owner="$(stat -c '%u:%g' "$path" 2>/dev/null || true)"
if [ "$actual_owner" != "$expected_owner" ]; then
  owner_state="${actual_owner:-missing}"
  status=fail
fi

actual_mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
if [ "$actual_mode" != "$expected_mode" ]; then
  mode_state="${actual_mode:-missing}"
  status=fail
fi

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$status" "$declared_size" "$allocated" "$used" "$lv_state" "$fs_state" "$uuid_state" "$mount_state" "$owner_state" "$mode_state"

if [ "$status" = ok ]; then
  exit 0
else
  exit 1
fi
"#;

    let output = remote_script_raw(
        context,
        host,
        script,
        &[
            &volume.id,
            &volume.lv,
            &volume.path,
            &volume.size,
            &volume.fs_type,
            &volume.uuid,
            &volume.host_uid,
            &volume.host_gid,
            &volume.mode,
        ],
    )?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let line = stdout
        .lines()
        .last()
        .ok_or_else(|| format!("[{host}/{}] check returned no output", volume.id))?;
    let row = parse_check_row(line)?;

    if !stderr.trim().is_empty() {
        eprintln!("[{host}/{}] {}", volume.id, stderr.trim());
    }

    Ok(row)
}

fn parse_check_row(line: &str) -> Result<CheckRow, String> {
    let fields = line.split('\t').collect::<Vec<_>>();
    if fields.len() != 11 {
        return Err(format!(
            "invalid check output: expected 11 fields, got {}: {line}",
            fields.len()
        ));
    }

    Ok(CheckRow {
        volume: fields[0].to_string(),
        status: fields[1].to_string(),
        configured: fields[2].to_string(),
        allocated: fields[3].to_string(),
        used: fields[4].to_string(),
        lv: fields[5].to_string(),
        fs: fields[6].to_string(),
        uuid: fields[7].to_string(),
        mount: fields[8].to_string(),
        owner: fields[9].to_string(),
        mode: fields[10].to_string(),
    })
}

