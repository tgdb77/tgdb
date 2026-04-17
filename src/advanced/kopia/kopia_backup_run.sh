#!/bin/bash

# Kopia 備份：執行流程（run / ignore / snapshot）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_BACKUP_RUN_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_BACKUP_RUN_LOADED=1

cmd_generate_ignore() {
  load_system_config >/dev/null 2>&1 || true

  local backup_root ignore_file tgdb_name
  backup_root="$(tgdb_backup_root)"
  ignore_file="$(_kopia_ignore_file)"
  tgdb_name="$(basename "$TGDB_DIR" 2>/dev/null || echo "app")"

  mkdir -p "$TGDB_DIR" 2>/dev/null || true

  local custom=""
  if [ -f "$ignore_file" ]; then
    custom="$(awk '
      $0 ~ /^# --- TGDB CUSTOM BEGIN ---$/ {in=1; next}
      $0 ~ /^# --- TGDB CUSTOM END ---$/ {in=0; exit}
      in==1 {print}
    ' "$ignore_file" 2>/dev/null || true)"
  fi

  local tmp
  tmp="$(mktemp "$TGDB_DIR/.kopiaignore.tmp.XXXXXX" 2>/dev/null || true)"
  if [ -z "${tmp:-}" ]; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/tgdb_kopiaignore.XXXXXX")"
  fi

  {
    echo "# Kopia ignore 規則（.kopiaignore）"
    echo "#"
    echo "# 由 TGDB 產生：請使用「Kopia 管理」選單更新或編輯。"
    echo "# 說明："
    echo "# - 語法類似 .gitignore（常用：*、?；以 / 開頭表示從根目錄比對）。"
    echo "# - 設計目標：快照備份時排除 DB data 目錄，改由 db-dump（熱備）納入快照。"
    echo ""
    echo "# --- TGDB AUTO BEGIN ---"
    echo "# 1) 冷備份 tar.gz（$backup_root/backup）通常屬於備份產物，為避免重複/膨脹，預設略過。"
    echo "/backup/"
    echo ""
    echo "# 2) volume_dir（$backup_root/volume）預設不納入 TGDB 備份範圍；如需全量備份請自行移除。"
    echo "/volume/"
    echo ""
    echo "# 3) DB data 目錄（依 TGDB 部署慣例：${TGDB_DIR}/<實例>/{pgdata,rdata,mysql,mongo}）"
    echo "/${tgdb_name}/*/pgdata/"
    echo "/${tgdb_name}/*/rdata/"
    echo "/${tgdb_name}/*/mysql/"
    echo "/${tgdb_name}/*/mongo/"
    echo "/*/pgdata/"
    echo "/*/rdata/"
    echo "/*/mysql/"
    echo "/*/mongo/"
    echo ""
    echo "# 4) 對齊 tar 冷備份排除：Nginx cache"
    echo "/${tgdb_name}/nginx/cache/"
    echo "/nginx/cache/"
    echo "# --- TGDB AUTO END ---"
    echo ""
    echo "# --- TGDB CUSTOM BEGIN ---"
    if [ -n "${custom:-}" ]; then
      printf '%s\n' "$custom"
    else
      echo "# 你可以在此加入自訂排除規則，例如："
      echo "# /${tgdb_name}/some-app/cache/**"
    fi
    echo "# --- TGDB CUSTOM END ---"
  } >"$tmp"

  mv -f "$tmp" "$ignore_file" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  chmod 644 "$ignore_file" 2>/dev/null || true

  echo "✅ 已更新 .kopiaignore：$ignore_file"
  return 0
}

_kopia_stage_quadlet_units() {
  local backup_root dest
  backup_root="$(tgdb_backup_root)"
  dest="$(_kopia_quadlet_runtime_stage_dir)"

  mkdir -p "$backup_root" 2>/dev/null || true
  if ! _kopia_stage_runtime_quadlet_tree "$dest"; then
    tgdb_warn "找不到可同步的 TGDB Quadlet runtime，已略過。"
    return 0
  fi
  return 0
}

_kopia_ensure_container_running() {
  local name="${1:-kopia}"

  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法執行 Kopia snapshot。" 1 || true
    return 1
  fi

  if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
    return 0
  fi

  if ! podman container exists "$name" 2>/dev/null; then
    tgdb_fail "找不到容器：$name（請先部署 Kopia）。" 1 || true
    return 1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    _systemctl_user_try start --no-block -- "${name}.service" "container-${name}.service" >/dev/null 2>&1 || true
  fi
  podman start "$name" >/dev/null 2>&1 || true

  if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
    return 0
  fi

  tgdb_fail "啟動 Kopia 容器失敗：$name（請檢查單元/日誌）。" 1 || true
  return 1
}

_kopia_default_override_source_for_path() {
  local source_path="$1"
  [ -n "${source_path:-}" ] || return 1

  local user host
  user="${KOPIA_OVERRIDE_SOURCE_USER:-root}"
  host="${KOPIA_OVERRIDE_SOURCE_HOST:-tgdb-kopia}"
  printf '%s\n' "${user}@${host}:${source_path}"
}

_kopia_pick_override_source_for_path() {
  local name="${1:-kopia}" source_path="${2:-}"
  [ -n "${source_path:-}" ] || return 1

  local all_raw rc=0
  all_raw="$(_kopia_snapshot_list_text "$name" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"

  local line current_source="" current_path=""
  local first_source="" best_source="" best_ts="" ts
  while IFS= read -r line; do
    if [[ "$line" =~ ^([^[:space:]]+@[^[:space:]]+):(/.*)$ ]]; then
      current_source="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
      current_path="${BASH_REMATCH[2]}"
      if [ "$current_path" = "$source_path" ] && [ -z "${first_source:-}" ]; then
        first_source="$current_source"
      fi
      continue
    fi

    [ "${current_path:-}" = "$source_path" ] || continue
    if [[ "$line" =~ ^[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([0-9]{2}:[0-9]{2}:[0-9]{2})[[:space:]] ]]; then
      ts="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
      if [ -z "${best_ts:-}" ] || [[ "$ts" > "$best_ts" ]]; then
        best_ts="$ts"
        best_source="$current_source"
      fi
    fi
  done <<< "$all_raw"

  if [ -n "${best_source:-}" ]; then
    printf '%s\n' "$best_source"
    return 0
  fi
  if [ -n "${first_source:-}" ]; then
    printf '%s\n' "$first_source"
    return 0
  fi
  return 1
}

_kopia_snapshot_create() {
  local name="${1:-kopia}"
  shift || true
  local -a sources=("$@")
  if [ ${#sources[@]} -eq 0 ]; then
    sources=("/data")
  fi

  # /data 由 Kopia Quadlet 單元掛載（Volume=${backup_root}:/data:ro）
  # 為避免重部署後來源鍵（owner@host:path）漂移，逐來源指定 --override-source。
  local src out rc=0 override_source
  for src in "${sources[@]}"; do
    override_source="$(_kopia_pick_override_source_for_path "$name" "$src" 2>/dev/null || true)"
    if [ -z "${override_source:-}" ]; then
      override_source="$(_kopia_default_override_source_for_path "$src")"
    fi

    echo "ℹ️ 建立快照來源：$src（override-source=$override_source）"
    out="$(_kopia_exec "$name" kopia snapshot create --override-source "$override_source" "$src" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
      tgdb_fail "Kopia snapshot 失敗（source=$src）：$out" 1 || true
      echo "提示：請先執行「Kopia 遠端 Repository 設定」。"
      return "$rc"
    fi
    [ -n "${out:-}" ] && echo "$out"
  done

  return 0
}

_kopia_snapshot_sources() {
  # 目標對齊 backup.sh 的 tar 冷備份範圍：
  # - /data/<tgdb_name>（TGDB_DIR）
  # - /data/config
  # - /data/quadlet-runtime
  local backup_root tgdb_name
  backup_root="$(tgdb_backup_root)"
  tgdb_name="$(basename "$TGDB_DIR" 2>/dev/null || echo "app")"

  local -a paths=()
  if [ -d "$backup_root/$tgdb_name" ]; then
    paths+=("/data/$tgdb_name")
  else
    tgdb_warn "找不到主要備份目錄：$backup_root/$tgdb_name（本次改用 /data）。"
    printf '%s\n' "/data"
    return 0
  fi

  if [ -d "$backup_root/config" ]; then
    paths+=("/data/config")
  fi
  if [ -d "$backup_root/$(_kopia_quadlet_runtime_archive_dirname)" ]; then
    paths+=("/data/$(_kopia_quadlet_runtime_archive_dirname)")
  elif [ -d "$backup_root/quadlet" ]; then
    paths+=("/data/quadlet")
  fi

  printf '%s\n' "${paths[@]}"
  return 0
}

cmd_run() {
  load_system_config >/dev/null 2>&1 || true

  local lock_dir
  lock_dir="$(_kopia_lock_dir)"
  if ! _kopia_lock_acquire "$lock_dir"; then
    return 1
  fi
  trap '_kopia_lock_release "'"$lock_dir"'"' EXIT

  local backup_root
  backup_root="$(tgdb_backup_root)"
  mkdir -p "$backup_root" 2>/dev/null || true

  # 先同步 Quadlet runtime（保留在 $backup_root/quadlet-runtime，供快照納入）
  _kopia_stage_quadlet_units || return 1
  tgdb_timer_units_stage_to_persist || true

  # 更新 ignore 規則（自動排除 DB data）
  cmd_generate_ignore || return 1

  _kopia_ensure_container_running "kopia" || return 1
  _kopia_wait_exec_ready "kopia" || return 1
  if ! _kopia_repository_status "kopia" >/dev/null 2>&1; then
    tgdb_fail "尚未連接 Kopia Repository，請先執行「Kopia 遠端 Repository 設定」。" 1 || true
    return 1
  fi

  # DB dump（僅在偵測到目標時執行）
  if _kopia_has_db_dump_targets; then
    local pg_z="${TGDB_DBBACKUP_PG_DUMP_Z:-0}"
    TGDB_DBBACKUP_PG_DUMP_Z="$pg_z" bash "$KOPIA_DIR/dbadmin/dbbackup-cli.sh" export-all
  else
    echo "ℹ️ 未偵測到可匯出的 DB 目標（略過 DB dump）。"
  fi

  local -a snapshot_sources=()
  local src
  while IFS= read -r src; do
    [ -n "${src:-}" ] && snapshot_sources+=("$src")
  done < <(_kopia_snapshot_sources)

  echo "⏳ 正在建立 Kopia snapshot（來源：${snapshot_sources[*]}）..."
  _kopia_snapshot_create "kopia" "${snapshot_sources[@]}"

  echo "ℹ️ 正在重載 Kopia Server 設定..."
  _kopia_reload_server "kopia" || {
    tgdb_warn "重載 Kopia Server 失敗，Web UI 可能不會立即顯示最新快照。"
  }

  local ts status_file
  ts="$(date +%Y%m%d-%H%M%S)"
  status_file="$(_kopia_backup_status_file)"
  mkdir -p "$(dirname "$status_file")" 2>/dev/null || true
  {
    echo "last_run_at=$ts"
    echo "backup_root=$backup_root"
  } >"$status_file" 2>/dev/null || true
  chmod 600 "$status_file" 2>/dev/null || true

  echo "✅ 統一備份完成（$ts）"
  return 0
}
