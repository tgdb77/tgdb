#!/bin/bash

# 數據庫備份：Redis 匯出/匯入
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DBBACKUP_REDIS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DBBACKUP_REDIS_LOADED=1

_dbbackup_redis_export() {
  local container_name="$1" env_file="$2" instance_dir="$3" want_pause="${4:-1}"
  [ -n "$container_name" ] || return 1
  [ -f "$env_file" ] || return 1
  [ -n "${instance_dir:-}" ] || instance_dir="$(dirname "$env_file" 2>/dev/null || echo "")"

  _dbbackup_ensure_container_running "$container_name" || {
    local rc=$?
    _dbbackup_pause_on_error "$rc" || true
    return "$rc"
  }

  if ! podman exec "$container_name" sh -c 'command -v redis-cli >/dev/null 2>&1' 2>/dev/null; then
    tgdb_fail "容器內找不到 redis-cli：$container_name（此功能暫不支援該映像）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local password
  password="$(_dbbackup_env_get_kv "$env_file" "REDIS_PASSWORD" 2>/dev/null || true)"
  if [ -z "${password:-}" ]; then
    tgdb_fail "找不到 REDIS_PASSWORD：$env_file" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local out_dir ts out_rdb out_meta
  out_dir="$(_dbbackup_project_backup_dir "$instance_dir" "redis")" || return 1
  _dbbackup_ensure_dir_writable "$out_dir" || { _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."; return 1; }
  chmod 700 "$out_dir" 2>/dev/null || true
  echo "輸出目錄：$out_dir"
  echo "設定檔：$env_file"

  ts="$(date +%Y%m%d-%H%M%S)"
  out_rdb="$out_dir/${ts}.rdb"
  out_meta="$out_dir/${ts}.meta.conf"

  local tmp_rdb="/tmp/tgdb_${ts}.rdb"
  local dump_out="" dump_rc=0
  dump_out="$(podman exec -e TGDB_PASS="$password" -e TGDB_OUT="$tmp_rdb" \
    "$container_name" sh -c 'set -eu; redis-cli -h 127.0.0.1 -p 6379 -a "$TGDB_PASS" --rdb "$TGDB_OUT" >/dev/null' 2>&1)" || dump_rc=$?
  if [ "$dump_rc" -ne 0 ]; then
    tgdb_fail "匯出失敗：$container_name（$dump_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local cp_out="" cp_rc=0
  local tmp_out_rdb="${out_rdb}.tmp"
  rm -f -- "$tmp_out_rdb" 2>/dev/null || true
  cp_out="$(podman cp "${container_name}:${tmp_rdb}" "$tmp_out_rdb" 2>&1)" || cp_rc=$?
  if [ "$cp_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_rdb" >/dev/null 2>&1 || true
    tgdb_fail "無法從容器取回檔案：$container_name:$tmp_rdb（$cp_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi
  podman exec "$container_name" rm -f "$tmp_rdb" >/dev/null 2>&1 || true
  if ! mv -f -- "$tmp_out_rdb" "$out_rdb" 2>/dev/null; then
    rm -f -- "$tmp_out_rdb" 2>/dev/null || true
    tgdb_fail "匯出檔案寫入失敗（無法原子改名）：$tmp_out_rdb -> $out_rdb" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  {
    echo "created_at=$ts"
    echo "db_type=redis"
    echo "container_name=$container_name"
    echo "env_file=$env_file"
    echo "format=rdb"
  } >"$out_meta" 2>/dev/null || true
  chmod 600 "$out_meta" 2>/dev/null || true

  _dbbackup_prune_old_backups "$out_dir" "$(_dbbackup_max_keep_get)" "rdb" || true

  echo "✅ 匯出完成：$out_rdb"
  echo " - meta：$out_meta"
  _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
  return 0
}

_dbbackup_redis_stop_container_best_effort() {
  local container_name="$1"
  [ -n "$container_name" ] || return 1

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop "${container_name}.service" >/dev/null 2>&1 || true
  fi
  podman stop "$container_name" >/dev/null 2>&1 || true

  if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container_name"; then
    return 1
  fi
  return 0
}

_dbbackup_redis_start_container_best_effort() {
  local container_name="$1"
  [ -n "$container_name" ] || return 1

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user start "${container_name}.service" >/dev/null 2>&1 || true
  fi
  podman start "$container_name" >/dev/null 2>&1 || true

  if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container_name"; then
    return 0
  fi
  return 1
}

_dbbackup_redis_import_overwrite() {
  local container_name="$1" env_file="$2" instance_dir="$3" unit_path="$4" want_pause="${5:-1}" forced_rdb_path="${6:-}" assume_yes="${7:-0}"
  [ -n "$container_name" ] || return 1
  [ -f "$env_file" ] || return 1
  [ -f "$unit_path" ] || return 1
  [ -n "${instance_dir:-}" ] || instance_dir="$(dirname "$env_file" 2>/dev/null || echo "")"

  local rdb_dir rdb_path
  rdb_dir="$(_dbbackup_project_backup_dir "$instance_dir" "redis")" || return 1
  forced_rdb_path="$(_dbbackup_trim_ws "${forced_rdb_path:-}")"
  if [ -n "${forced_rdb_path:-}" ]; then
    rdb_path="$forced_rdb_path"
    if [ ! -f "$rdb_path" ]; then
      tgdb_fail "找不到備份檔：$rdb_path" 1 || true
      _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
      return 1
    fi
  else
    _dbbackup_pick_existing_backup_file "$rdb_dir" "rdb" rdb_path || return $?
  fi

  local password
  password="$(_dbbackup_env_get_kv "$env_file" "REDIS_PASSWORD" 2>/dev/null || true)"
  if [ -z "${password:-}" ]; then
    tgdb_fail "找不到 REDIS_PASSWORD：$env_file" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local host_data_dir
  host_data_dir="$(_dbbackup_unit_volume_host_for_container_path "$unit_path" "/data" 2>/dev/null || true)"
  if [ -z "${host_data_dir:-}" ] || [ ! -d "$host_data_dir" ]; then
    tgdb_fail "無法解析/找到資料目錄（/data 掛載）：$unit_path" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  echo "⚠️ 重要提醒：此操作會『覆蓋』目標 Redis 的資料檔。"
  echo " - 目標容器：$container_name"
  echo " - 目標資料目錄：$host_data_dir"
  echo " - 匯入檔案：$rdb_path"
  echo "建議：先停止所有使用此 Redis 的上游服務，避免重啟後資料不一致。"

  if [ "${assume_yes:-0}" != "1" ]; then
    if ! ui_confirm_yn "確認繼續覆蓋還原嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
      local rc=$?
      [ "$rc" -eq 2 ] && return 2
      return 0
    fi
  fi

  if ! _dbbackup_redis_stop_container_best_effort "$container_name"; then
    tgdb_fail "停止容器失敗：$container_name（請先手動停止後再重試）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  # 覆蓋還原：清掉舊持久化檔（尤其 AOF），再放入 dump.rdb
  rm -rf -- "$host_data_dir/appendonly.aof" "$host_data_dir/appendonlydir" "$host_data_dir/appendonly" 2>/dev/null || true
  rm -f -- "$host_data_dir/dump.rdb" 2>/dev/null || true

  if ! cp -f "$rdb_path" "$host_data_dir/dump.rdb" 2>/dev/null; then
    tgdb_fail "複製失敗：$rdb_path -> $host_data_dir/dump.rdb" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi
  chmod 600 "$host_data_dir/dump.rdb" 2>/dev/null || true

  if ! _dbbackup_redis_start_container_best_effort "$container_name"; then
    tgdb_fail "啟動容器失敗：$container_name（請檢查單元/日誌）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  # 基本驗證（可略過）
  if podman exec -e TGDB_PASS="$password" "$container_name" sh -c 'redis-cli -h 127.0.0.1 -p 6379 -a "$TGDB_PASS" ping 2>/dev/null | grep -q PONG' 2>/dev/null; then
    echo "✅ 匯入完成：Redis 已回應 PONG"
  else
    tgdb_warn "匯入後驗證失敗：未取得 PONG（可能仍在載入或密碼不符）。"
  fi

  _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
  return 0
}
