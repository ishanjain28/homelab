use crate::models::{ActualVolume, Context, Volume};
use crate::remote::remote_script_raw;
use crate::util::non_empty_lines;
use std::process::Command;

pub fn hosts(context: &Context, requested_hosts: &[String]) -> Result<Vec<String>, String> {
    if !requested_hosts.is_empty() {
        return Ok(requested_hosts.to_vec());
    }

    let output = nix_eval_raw(
        &context.flake,
        "nixosConfigurations",
        "machines: builtins.concatStringsSep \"\\n\" (builtins.attrNames machines)",
    )?;
    Ok(non_empty_lines(&output))
}

pub fn volumes(context: &Context, host: &str) -> Result<Vec<Volume>, String> {
    let attr = format!("nixosConfigurations.{host}.config.system.homelab.volumes");
    let apply = r#"volumes:
      builtins.concatStringsSep "\n" (
        builtins.attrValues (
          builtins.mapAttrs (
            name: value:
              builtins.concatStringsSep "\t" [
                name
                value.lvPath
                value.hostPath
                value.size
                value.fsType
                value.uuid
                (builtins.toString value.owner.hostUid)
                (builtins.toString value.owner.hostGid)
                value.owner.mode
                value.ownerService
              ]
          ) volumes
        )
      )"#;

    let output = nix_eval_raw(&context.flake, &attr, apply)?;
    output
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(parse_volume)
        .collect()
}

pub fn actual_volumes(context: &Context, host: &str) -> Result<Vec<ActualVolume>, String> {
    let script = r#"
set -euo pipefail

if ! vgs pool >/dev/null 2>&1; then
  exit 0
fi

lvs --noheadings -o lv_path pool 2>/dev/null | while read -r lv; do
  [ -n "$lv" ] || continue

  uuid="$(blkid -s UUID -o value "$lv" 2>/dev/null || true)"
  [ -n "$uuid" ] || continue

  fs_type="$(blkid -s TYPE -o value "$lv" 2>/dev/null || true)"
  size_bytes="$(blockdev --getsize64 "$lv" 2>/dev/null || true)"
  canonical_lv="$(readlink -f "$lv" 2>/dev/null || printf '%s' "$lv")"
  mountpoint="$(
    findmnt -rn -o SOURCE,TARGET 2>/dev/null \
      | while read -r source target; do
          canonical_source="$(readlink -f "$source" 2>/dev/null || printf '%s' "$source")"
          if [ "$canonical_source" = "$canonical_lv" ]; then
            printf '%s\n' "$target"
            break
          fi
        done
  )"

  printf '%s\t%s\t%s\t%s\t%s\n' "$uuid" "$lv" "$fs_type" "$size_bytes" "$mountpoint"
done
"#;

    let output = remote_script_raw(context, host, script, &[])?;
    if !output.status.success() {
        return Err(format!(
            "[{host}] failed to scan actual volumes:\n{}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| parse_actual_volume(host, line))
        .collect()
}

fn nix_eval_raw(flake: &str, attr: &str, apply: &str) -> Result<String, String> {
    let output = Command::new("nix")
        .args(["eval", "--raw", &format!("{flake}#{attr}"), "--apply", apply])
        .output()
        .map_err(|error| format!("failed to run nix eval: {error}"))?;

    if !output.status.success() {
        return Err(format!(
            "nix eval failed:\n{}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn parse_volume(line: &str) -> Result<Volume, String> {
    let fields = line.split('\t').collect::<Vec<_>>();
    if fields.len() != 10 {
        return Err(format!(
            "invalid volume metadata line: expected 10 fields, got {}: {line}",
            fields.len()
        ));
    }

    Ok(Volume {
        id: fields[0].to_string(),
        lv: fields[1].to_string(),
        path: fields[2].to_string(),
        size: fields[3].to_string(),
        fs_type: fields[4].to_string(),
        uuid: fields[5].to_string(),
        host_uid: fields[6].to_string(),
        host_gid: fields[7].to_string(),
        mode: fields[8].to_string(),
        owner_service: fields[9].to_string(),
    })
}

fn parse_actual_volume(host: &str, line: &str) -> Result<ActualVolume, String> {
    let fields = line.split('\t').collect::<Vec<_>>();
    if fields.len() != 5 {
        return Err(format!(
            "[{host}] invalid actual volume line: expected 5 fields, got {}: {line}",
            fields.len()
        ));
    }

    Ok(ActualVolume {
        host: host.to_string(),
        uuid: fields[0].to_string(),
        lv: fields[1].to_string(),
        fs_type: fields[2].to_string(),
        size_bytes: fields[3].to_string(),
        mountpoint: fields[4].to_string(),
    })
}

