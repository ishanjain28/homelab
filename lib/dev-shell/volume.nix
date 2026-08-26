{ pkgs }:

pkgs.writeShellApplication {
  name = "volume";
  runtimeInputs = with pkgs; [
    coreutils
    jq
    nix
    openssh
  ];
  text = ''
    # shellcheck disable=SC2016,SC2029
    set -euo pipefail

    flake="''${HOMELAB_FLAKE:-.}"
    ssh_config="$HOME/.ssh/config"
    if [ ! -r "$ssh_config" ]; then
      ssh_config=/dev/null
    fi

    usage() {
      cat <<'EOF'
    usage:
      volume check [host...]
      volume apply [host...]
      volume delete <host> <volume-id> [volume-id...]

    check:
      SSH into each host and verify declared homelab volumes.

    apply:
      SSH into each host and apply volume disk changes step by step.
      Missing LVs/filesystems and size increases are confirmed before running.
      Size decreases require exact typed confirmation.

    delete:
      Delete a declared volume from one host after verifying it has no user data.
      The filesystem may contain only lost+found.
    EOF
    }

    hosts() {
      if [ "$#" -gt 0 ]; then
        printf '%s\n' "$@"
      else
        nix eval --json "$flake#nixosConfigurations" --apply builtins.attrNames | jq -r '.[]'
      fi
    }

    volume_lines() {
      local host="$1"
      nix eval --json "$flake#nixosConfigurations.$host.config.system.homelab.volumes" \
        | jq -r '
          to_entries[]
          | [
              .key,
              .value.lvPath,
              .value.hostPath,
              .value.size,
              .value.fsType,
              .value.uuid,
              (.value.owner.hostUid | tostring),
              (.value.owner.hostGid | tostring),
              .value.owner.mode,
              .value.ownerService
            ]
          | @tsv
        '
    }

    confirm() {
      local prompt="$1"
      local reply

      printf '%s [yes/no] ' "$prompt" > /dev/tty
      read -r reply < /dev/tty
      [ "$reply" = "yes" ]
    }

    confirm_exact() {
      local prompt="$1"
      local expected="$2"
      local reply

      printf '%s\nType exactly: %s\n> ' "$prompt" "$expected" > /dev/tty
      read -r reply < /dev/tty
      [ "$reply" = "$expected" ]
    }

    remote_sudo() {
      local host="$1"
      shift
      # shellcheck disable=SC2029
      ssh -n -F "$ssh_config" "$host" sudo "$@"
    }

    check_volume() {
      local host="$1"
      local id="$2"
      local lv="$3"
      local path="$4"
      local size="$5"
      local fs_type="$6"
      local uuid="$7"
      local host_uid="$8"
      local host_gid="$9"
      local mode="''${10}"

      ssh -F "$ssh_config" "$host" sudo bash -s -- "$id" "$lv" "$path" "$size" "$fs_type" "$uuid" "$host_uid" "$host_gid" "$mode" <<'REMOTE_CHECK'
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
    status=0

    echo "checking $id"

    if [ ! -b "$lv" ]; then
      echo "  missing block device: $lv"
      status=1
    else
      actual_size="$(blockdev --getsize64 "$lv")"
      if [ "$actual_size" -gt "$expected_size" ]; then
        echo "  declared size is smaller than actual: declared $declared_size, actual $actual_size bytes"
        status=1
      elif [ "$actual_size" -lt "$expected_size" ]; then
        echo "  actual size is smaller than declared: declared $declared_size, actual $actual_size bytes"
        status=1
      fi

      actual_type="$(blkid -s TYPE -o value "$lv" 2>/dev/null || true)"
      if [ "$actual_type" != "$expected_type" ]; then
        echo "  type mismatch: expected $expected_type, got ''${actual_type:-missing}"
        status=1
      fi

      actual_uuid="$(blkid -s UUID -o value "$lv" 2>/dev/null || true)"
      if [ "$actual_uuid" != "$expected_uuid" ]; then
        echo "  uuid mismatch: expected $expected_uuid, got ''${actual_uuid:-missing}"
        status=1
      fi
    fi

    if ! findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then
      echo "  not mounted: $path"
      status=1
    else
      expected_source="$(readlink -f "$lv" 2>/dev/null || true)"
      actual_source="$(findmnt -rn -o SOURCE --mountpoint "$path" 2>/dev/null || true)"
      actual_source="$(readlink -f "$actual_source" 2>/dev/null || true)"
      if [ "$actual_source" != "$expected_source" ]; then
        echo "  source mismatch: expected $expected_source, got ''${actual_source:-missing}"
        status=1
      fi
    fi

    actual_owner="$(stat -c '%u:%g' "$path" 2>/dev/null || true)"
    if [ "$actual_owner" != "$expected_owner" ]; then
      echo "  owner mismatch: expected $expected_owner, got ''${actual_owner:-missing}"
      status=1
    fi

    actual_mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
    if [ "$actual_mode" != "$expected_mode" ]; then
      echo "  mode mismatch: expected $expected_mode, got ''${actual_mode:-missing}"
      status=1
    fi

    exit "$status"
    REMOTE_CHECK
    }

    ensure_mount_owner() {
      local host="$1"
      local id="$2"
      local lv="$3"
      local path="$4"
      local host_uid="$5"
      local host_gid="$6"
      local mode="$7"

      if ! remote_sudo "$host" findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then
        if confirm "[$host/$id] mount $path"; then
          remote_sudo "$host" mkdir -p "$path"
          remote_sudo "$host" mount "$lv" "$path"
        fi
      fi

      local actual_owner
      local actual_mode
      actual_owner="$(remote_sudo "$host" stat -c '%u:%g' "$path" 2>/dev/null || true)"
      actual_mode="$(remote_sudo "$host" stat -c '%a' "$path" 2>/dev/null || true)"

      if [ "$actual_owner" != "$host_uid:$host_gid" ] || [ "$actual_mode" != "$(printf '%s' "$mode" | sed 's/^0*//')" ]; then
        if confirm "[$host/$id] set $path owner=$host_uid:$host_gid mode=$mode"; then
          remote_sudo "$host" chown "$host_uid:$host_gid" "$path"
          remote_sudo "$host" chmod "$mode" "$path"
        fi
      fi
    }

    apply_volume() {
      local host="$1"
      local id="$2"
      local lv="$3"
      local path="$4"
      local size="$5"
      local fs_type="$6"
      local uuid="$7"
      local host_uid="$8"
      local host_gid="$9"
      local mode="''${10}"
      local owner_service="''${11}"
      local lv_name
      local actual_type
      local actual_uuid
      local expected_size
      local actual_size

      lv_name="$(basename "$lv")"
      expected_size="$(numfmt --from=iec "$size")"

      if ! remote_sudo "$host" vgs pool >/dev/null 2>&1; then
        echo "[$host/$id] missing LVM volume group: pool" >&2
        return 1
      fi

      if ! remote_sudo "$host" test -b "$lv"; then
        if confirm "[$host/$id] create $lv with size $size"; then
          remote_sudo "$host" lvcreate --yes --size "$size" --name "$lv_name" pool
        else
          return 1
        fi
      fi

      actual_type="$(remote_sudo "$host" blkid -s TYPE -o value "$lv" 2>/dev/null || true)"
      if [ -z "$actual_type" ]; then
        if confirm "[$host/$id] create $fs_type filesystem on $lv with UUID $uuid"; then
          remote_sudo "$host" "mkfs.$fs_type" -F -U "$uuid" "$lv"
        else
          return 1
        fi
      elif [ "$actual_type" != "$fs_type" ]; then
        echo "[$host/$id] filesystem type mismatch: expected $fs_type, got $actual_type" >&2
        return 1
      fi

      actual_uuid="$(remote_sudo "$host" blkid -s UUID -o value "$lv" 2>/dev/null || true)"
      if [ "$actual_uuid" != "$uuid" ]; then
        echo "[$host/$id] UUID mismatch: expected $uuid, got ''${actual_uuid:-missing}" >&2
        return 1
      fi

      actual_size="$(remote_sudo "$host" blockdev --getsize64 "$lv")"
      if [ "$actual_size" -lt "$expected_size" ]; then
        if confirm "[$host/$id] grow $lv from $actual_size bytes to $size"; then
          remote_sudo "$host" lvextend --yes --size "$size" "$lv"
          remote_sudo "$host" resize2fs "$lv"
        else
          return 1
        fi
      elif [ "$actual_size" -gt "$expected_size" ]; then
        echo "[$host/$id] declared size is smaller than current LV"
        echo "  current:  $actual_size bytes"
        echo "  declared: $expected_size bytes ($size)"
        if remote_sudo "$host" findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then
          remote_sudo "$host" df -h "$path"
        else
          echo "  usage: unavailable because $path is not mounted"
        fi

        if confirm_exact "[$host/$id] shrink $lv to $size. This stops container@$owner_service and rewrites filesystem/LV size." "shrink $host/$id"; then
          remote_sudo "$host" systemctl stop "container@$owner_service.service"
          remote_sudo "$host" umount "$path"
          remote_sudo "$host" e2fsck -fy "$lv"
          remote_sudo "$host" lvreduce --yes --resizefs --size "$size" "$lv"
          remote_sudo "$host" mount "$lv" "$path"
          remote_sudo "$host" chown "$host_uid:$host_gid" "$path"
          remote_sudo "$host" chmod "$mode" "$path"
          remote_sudo "$host" systemctl start "container@$owner_service.service"
        else
          return 1
        fi
      fi

      ensure_mount_owner "$host" "$id" "$lv" "$path" "$host_uid" "$host_gid" "$mode"
    }

    delete_volume() {
      local host="$1"
      local wanted_id="$2"
      local line
      local id
      local lv
      local path
      local size
      local fs_type
      local uuid
      local host_uid
      local host_gid
      local mode
      local owner_service

      line="$(volume_lines "$host" | awk -F '\t' -v wanted="$wanted_id" '$1 == wanted { print; found = 1 } END { if (!found) exit 1 }')" || {
        echo "[$host/$wanted_id] no declared volume found" >&2
        return 1
      }

      IFS=$'\t' read -r id lv path size fs_type uuid host_uid host_gid mode owner_service <<< "$line"

      if ! remote_sudo "$host" test -b "$lv"; then
        echo "[$host/$id] missing block device: $lv" >&2
        return 1
      fi

      local actual_type
      local actual_uuid
      actual_type="$(remote_sudo "$host" blkid -s TYPE -o value "$lv" 2>/dev/null || true)"
      actual_uuid="$(remote_sudo "$host" blkid -s UUID -o value "$lv" 2>/dev/null || true)"

      if [ "$actual_type" != "$fs_type" ]; then
        echo "[$host/$id] filesystem type mismatch: expected $fs_type, got ''${actual_type:-missing}" >&2
        return 1
      fi

      if [ "$actual_uuid" != "$uuid" ]; then
        echo "[$host/$id] UUID mismatch: expected $uuid, got ''${actual_uuid:-missing}" >&2
        return 1
      fi

      if ! remote_sudo "$host" findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then
        if confirm "[$host/$id] mount $lv at $path to inspect whether it is empty"; then
          remote_sudo "$host" mkdir -p "$path"
          remote_sudo "$host" mount "$lv" "$path"
        else
          return 1
        fi
      fi

      echo "[$host/$id] current usage"
      remote_sudo "$host" df -h "$path"
      # shellcheck disable=SC2016
      remote_sudo "$host" bash -c 'printf "allocated bytes: "; blockdev --getsize64 "$1"' bash "$lv"
      # shellcheck disable=SC2016
      remote_sudo "$host" bash -c 'printf "used bytes: "; df -B1 --output=used "$1" | tail -n 1 | tr -d " "' bash "$path"

      # shellcheck disable=SC2016
      if remote_sudo "$host" bash -c 'find "$1" -mindepth 1 ! -name lost+found -print -quit | grep -q .' bash "$path"; then
        echo "[$host/$id] refusing to delete: volume is not empty" >&2
        # shellcheck disable=SC2016
        remote_sudo "$host" bash -c 'find "$1" -mindepth 1 ! -name lost+found -maxdepth 2 -print | sed -n "1,20p"' bash "$path"
        return 1
      fi

      if confirm_exact "[$host/$id] delete $lv. This stops container@$owner_service, unmounts $path, and removes the LV." "delete $host/$id"; then
        remote_sudo "$host" systemctl stop "container@$owner_service.service"
        remote_sudo "$host" umount "$path"
        remote_sudo "$host" lvremove --yes "$lv"
      else
        return 1
      fi
    }

    run_check() {
      local host
      local had_volume
      local status=0

      while IFS= read -r host; do
        had_volume=0
        printf '##########\n## Host: %s\n##########\n' "$host"
        while IFS=$'\t' read -r id lv path size fs_type uuid host_uid host_gid mode owner_service; do
          [ -n "$id" ] || continue
          had_volume=1
          if ! check_volume "$host" "$id" "$lv" "$path" "$size" "$fs_type" "$uuid" "$host_uid" "$host_gid" "$mode" "$owner_service"; then
            status=1
          fi
        done < <(volume_lines "$host")
        if [ "$had_volume" -eq 0 ]; then
          echo "no homelab volumes declared for $host"
        fi
      done < <(hosts "$@")

      exit "$status"
    }

    run_apply() {
      local host
      local had_volume

      while IFS= read -r host; do
        had_volume=0
        printf '##########\n## Host: %s\n##########\n' "$host"
        while IFS=$'\t' read -r id lv path size fs_type uuid host_uid host_gid mode owner_service; do
          [ -n "$id" ] || continue
          had_volume=1
          apply_volume "$host" "$id" "$lv" "$path" "$size" "$fs_type" "$uuid" "$host_uid" "$host_gid" "$mode" "$owner_service"
        done < <(volume_lines "$host")
        if [ "$had_volume" -eq 0 ]; then
          echo "no homelab volumes declared for $host"
        fi
      done < <(hosts "$@")
    }

    run_delete() {
      local host="''${1:-}"
      if [ -z "$host" ] || [ "$#" -lt 2 ]; then
        usage >&2
        exit 2
      fi
      shift

      local volume_id
      for volume_id in "$@"; do
        delete_volume "$host" "$volume_id"
      done
    }

    cmd="''${1:-}"
    if [ -z "$cmd" ]; then
      usage
      exit 2
    fi
    shift

    case "$cmd" in
      check)
        run_check "$@"
        ;;
      apply)
        run_apply "$@"
        ;;
      delete)
        run_delete "$@"
        ;;
      -h|--help|help)
        usage
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
  '';
}
