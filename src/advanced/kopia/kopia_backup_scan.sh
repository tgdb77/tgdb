#!/bin/bash

# Kopia 備份：掃描與目標偵測
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_BACKUP_SCAN_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_BACKUP_SCAN_LOADED=1

_kopia_repository_status() {
  local name="${1:-kopia}"
  _kopia_exec "$name" kopia repository status
}

_kopia_container_has_rclone() {
  local name="${1:-kopia}"
  podman exec "$name" sh -lc 'command -v rclone >/dev/null 2>&1'
}

_kopia_container_has_rclone_config() {
  local name="${1:-kopia}"
  podman exec "$name" sh -lc '[ -f /app/rclone/rclone.conf ]'
}

_kopia_container_has_remote_name() {
  local name="${1:-kopia}" remote_name="${2:-}"
  [ -n "${remote_name:-}" ] || return 1
  podman exec "$name" rclone listremotes --config /app/rclone/rclone.conf 2>/dev/null | grep -qx "${remote_name}:"
}

_kopia_repo_create_rclone() {
  local name="${1:-kopia}" remote_path="${2:-}"
  [ -n "${remote_path:-}" ] || return 1

  _kopia_exec "$name" kopia repository create rclone \
    --remote-path="$remote_path" \
    --rclone-exe=rclone \
    --rclone-env=RCLONE_CONFIG=/app/rclone/rclone.conf
}

_kopia_repo_connect_rclone() {
  local name="${1:-kopia}" remote_path="${2:-}"
  [ -n "${remote_path:-}" ] || return 1

  _kopia_exec "$name" kopia repository connect rclone \
    --remote-path="$remote_path" \
    --rclone-exe=rclone \
    --rclone-env=RCLONE_CONFIG=/app/rclone/rclone.conf
}

_kopia_unit_has_label() {
  local file="$1" want="$2"
  [ -f "$file" ] || return 1
  [ -n "${want:-}" ] || return 1
  awk -v want="$want" '
    /^[[:space:]]*Label[[:space:]]*=/ {
      line=$0
      sub(/^[[:space:]]*Label[[:space:]]*=[[:space:]]*/, "", line)
      sub(/[[:space:]]*(#.*)?$/, "", line)
      gsub(/^"|"$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == want) { found=1; exit }
      if (index(line, want) > 0) { found=1; exit }
    }
    END{ if (found==1) exit 0; exit 1 }
  ' "$file" 2>/dev/null
}

_kopia_unit_volume_host_for_container_path() {
  local file="$1" container_path="$2"
  [ -f "$file" ] || return 1
  [ -n "${container_path:-}" ] || return 1

  awk -F= -v cpath="$container_path" '
    $1=="Volume" {
      v=$2
      n=split(v, a, ":")
      if (n>=2 && a[2]==cpath) {
        print a[1]
        found=1
        exit
      }
    }
    END{ if (found==1) exit 0; exit 1 }
  ' "$file" 2>/dev/null
}

_kopia_scan_container_units() {
  if declare -F rm_list_tgdb_runtime_quadlet_files_by_mode >/dev/null 2>&1; then
    rm_list_tgdb_runtime_quadlet_files_by_mode rootless 2>/dev/null | awk -F'\t' 'NF >= 4 && $3 ~ /\.container$/ { print $4 }'
  fi

  local persist_dir
  persist_dir="$(rm_persist_config_dir 2>/dev/null || echo "")"
  if [ -n "${persist_dir:-}" ] && [ -d "$persist_dir" ]; then
    find "$persist_dir" -type f -name "*.container" -print 2>/dev/null || true
  fi
}

_kopia_collect_db_data_dirs() {
  # 輸出：每行一個「host 絕對路徑」的 DB data dir（Postgres / Redis / MySQL / MariaDB / MongoDB）
  local file
  while IFS= read -r file; do
    [ -f "$file" ] || continue

    if _kopia_unit_has_label "$file" "tgdb_db=postgres"; then
      _kopia_unit_volume_host_for_container_path "$file" "/var/lib/postgresql/data" 2>/dev/null || true
    fi
    if _kopia_unit_has_label "$file" "tgdb_db=redis"; then
      _kopia_unit_volume_host_for_container_path "$file" "/data" 2>/dev/null || true
    fi
    if _kopia_unit_has_label "$file" "tgdb_db=mysql"; then
      _kopia_unit_volume_host_for_container_path "$file" "/var/lib/mysql" 2>/dev/null || true
    fi
    if _kopia_unit_has_label "$file" "tgdb_db=mariadb"; then
      _kopia_unit_volume_host_for_container_path "$file" "/var/lib/mysql" 2>/dev/null || true
    fi
    if _kopia_unit_has_label "$file" "tgdb_db=mongo"; then
      _kopia_unit_volume_host_for_container_path "$file" "/data/db" 2>/dev/null || true
    fi
  done < <(_kopia_scan_container_units)
}

_kopia_has_db_dump_targets() {
  local host_data_dir
  while IFS= read -r host_data_dir; do
    [ -n "${host_data_dir:-}" ] || continue
    local instance_dir env_file
    instance_dir="$(dirname "$host_data_dir" 2>/dev/null || echo "")"
    env_file="$instance_dir/.env"
    if [ -f "$env_file" ]; then
      return 0
    fi
  done < <(_kopia_collect_db_data_dirs)
  return 1
}
