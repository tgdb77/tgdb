#!/bin/bash

# 數據庫備份：PostgreSQL 匯出/匯入
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DBBACKUP_POSTGRES_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DBBACKUP_POSTGRES_LOADED=1

_dbbackup_postgres_export() {
  local container_name="$1" env_file="$2" instance_dir="$3" want_pause="${4:-1}" forced_globals="${5:-}"
  [ -n "$container_name" ] || return 1
  [ -f "$env_file" ] || return 1
  [ -n "${instance_dir:-}" ] || instance_dir="$(dirname "$env_file" 2>/dev/null || echo "")"

  _dbbackup_ensure_container_running "$container_name" || {
    local rc=$?
    _dbbackup_pause_on_error "$rc" || true
    return "$rc"
  }

  if ! podman exec "$container_name" sh -c 'command -v pg_dump >/dev/null 2>&1' 2>/dev/null; then
    tgdb_fail "容器內找不到 pg_dump：$container_name（此功能暫不支援該映像）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local db user password
  db="$(_dbbackup_env_get_kv "$env_file" "POSTGRES_DB" 2>/dev/null || true)"
  user="$(_dbbackup_env_get_kv "$env_file" "POSTGRES_USER" 2>/dev/null || true)"
  password="$(_dbbackup_env_get_kv "$env_file" "POSTGRES_PASSWORD" 2>/dev/null || true)"
  [ -z "${db:-}" ] && db="postgres"
  [ -z "${user:-}" ] && user="postgres"

  if [ -z "${password:-}" ]; then
    tgdb_fail "找不到 POSTGRES_PASSWORD：$env_file" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local include_globals="N"
  forced_globals="$(_dbbackup_trim_ws "${forced_globals:-}")"
  if [ -n "${forced_globals:-}" ]; then
    case "$forced_globals" in
      Y|y) include_globals="Y" ;;
      N|n) include_globals="N" ;;
      *) include_globals="N" ;;
    esac
  else
    if ui_confirm_yn "是否同時匯出 roles/權限（globals-only）？(y/N，預設 N，輸入 0 取消): " "N"; then
      include_globals="Y"
    else
      local rc=$?
      [ "$rc" -eq 2 ] && return 2
    fi
  fi

  local out_dir ts out_dump out_globals out_meta
  out_dir="$(_dbbackup_project_backup_dir "$instance_dir" "postgres")" || return 1
  _dbbackup_ensure_dir_writable "$out_dir" || { _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."; return 1; }
  chmod 700 "$out_dir" 2>/dev/null || true
  echo "輸出目錄：$out_dir"
  echo "連線資訊：db=$db / user=$user"
  echo "設定檔：$env_file"

  ts="$(date +%Y%m%d-%H%M%S)"
  out_dump="$out_dir/${ts}.dump"
  out_globals="$out_dir/${ts}.globals.sql"
  out_meta="$out_dir/${ts}.meta.conf"

  local pg_dump_z="${TGDB_DBBACKUP_PG_DUMP_Z:-6}"
  if [[ ! "${pg_dump_z:-}" =~ ^[0-9]+$ ]] || [ "$pg_dump_z" -lt 0 ] || [ "$pg_dump_z" -gt 9 ] 2>/dev/null; then
    pg_dump_z=6
  fi

  local tmp_dump="/tmp/tgdb_${ts}.dump"
  local dump_out="" dump_rc=0
  dump_out="$(podman exec -e TGDB_DB="$db" -e TGDB_USER="$user" -e TGDB_PASS="$password" -e TGDB_Z="$pg_dump_z" -e TGDB_OUT="$tmp_dump" \
    "$container_name" sh -c 'set -eu; export PGPASSWORD="$TGDB_PASS"; pg_dump -h 127.0.0.1 -p 5432 -U "$TGDB_USER" -d "$TGDB_DB" -Fc -Z "$TGDB_Z" -f "$TGDB_OUT"' 2>&1)" || dump_rc=$?
  if [ "$dump_rc" -ne 0 ]; then
    if printf '%s' "$dump_out" | grep -qi "role .*does not exist"; then
      tgdb_fail "匯出失敗：$container_name（$dump_out）
提示：你目前的 POSTGRES_USER=$user，但資料庫內可能沒有這個 role。若曾經已有 pgdata，改 .env 不會自動建立角色，請修正 $env_file 或在容器內建立 role。" 1 || true
    else
      tgdb_fail "匯出失敗：$container_name（$dump_out）" 1 || true
    fi
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local cp_out="" cp_rc=0
  local tmp_out_dump="${out_dump}.tmp"
  rm -f -- "$tmp_out_dump" 2>/dev/null || true
  cp_out="$(podman cp "${container_name}:${tmp_dump}" "$tmp_out_dump" 2>&1)" || cp_rc=$?
  if [ "$cp_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_dump" >/dev/null 2>&1 || true
    tgdb_fail "無法從容器取回檔案：$container_name:$tmp_dump（$cp_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi
  podman exec "$container_name" rm -f "$tmp_dump" >/dev/null 2>&1 || true
  if ! mv -f -- "$tmp_out_dump" "$out_dump" 2>/dev/null; then
    rm -f -- "$tmp_out_dump" 2>/dev/null || true
    tgdb_fail "匯出檔案寫入失敗（無法原子改名）：$tmp_out_dump -> $out_dump" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  if [ "$include_globals" = "Y" ]; then
    local tmp_globals="/tmp/tgdb_${ts}_globals.sql"
    if podman exec -e TGDB_USER="$user" -e TGDB_PASS="$password" -e TGDB_OUT="$tmp_globals" \
      "$container_name" sh -c 'set -eu; export PGPASSWORD="$TGDB_PASS"; pg_dumpall -h 127.0.0.1 -p 5432 -U "$TGDB_USER" --globals-only >"$TGDB_OUT"' 2>/dev/null; then
      podman cp "${container_name}:${tmp_globals}" "$out_globals" 2>/dev/null || true
      podman exec "$container_name" rm -f "$tmp_globals" >/dev/null 2>&1 || true
    else
      tgdb_warn "globals-only 匯出失敗（已略過）。"
    fi
  fi

  {
    echo "created_at=$ts"
    echo "db_type=postgres"
    echo "container_name=$container_name"
    echo "env_file=$env_file"
    echo "db_name=$db"
    echo "db_user=$user"
    echo "format=pg_dump_custom"
    echo "pg_dump_z=$pg_dump_z"
    echo "include_globals=$include_globals"
  } >"$out_meta" 2>/dev/null || true
  chmod 600 "$out_meta" 2>/dev/null || true

  _dbbackup_prune_old_backups "$out_dir" "$(_dbbackup_max_keep_get)" "dump" || true

  echo "✅ 匯出完成：$out_dump"
  if [ -f "$out_globals" ]; then
    echo " - globals：$out_globals"
  fi
  echo " - meta：$out_meta"
  _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
  return 0
}

_dbbackup_postgres_import_overwrite() {
  local container_name="$1" env_file="$2" instance_dir="$3" want_pause="${4:-1}" forced_dump_path="${5:-}" assume_yes="${6:-0}"
  [ -n "$container_name" ] || return 1
  [ -f "$env_file" ] || return 1
  [ -n "${instance_dir:-}" ] || instance_dir="$(dirname "$env_file" 2>/dev/null || echo "")"

  _dbbackup_ensure_container_running "$container_name" || {
    local rc=$?
    _dbbackup_pause_on_error "$rc" || true
    return "$rc"
  }

  if ! podman exec "$container_name" sh -c 'command -v pg_restore >/dev/null 2>&1 && command -v psql >/dev/null 2>&1' 2>/dev/null; then
    tgdb_fail "容器內缺少 pg_restore/psql：$container_name（此功能暫不支援該映像）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local dump_dir dump_path
  dump_dir="$(_dbbackup_project_backup_dir "$instance_dir" "postgres")" || return 1
  forced_dump_path="$(_dbbackup_trim_ws "${forced_dump_path:-}")"
  if [ -n "${forced_dump_path:-}" ]; then
    dump_path="$forced_dump_path"
    if [ ! -f "$dump_path" ]; then
      tgdb_fail "找不到備份檔：$dump_path" 1 || true
      _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
      return 1
    fi
  else
    _dbbackup_pick_existing_backup_file "$dump_dir" "dump" dump_path || return $?
  fi

  local globals_path=""
  globals_path="${dump_path%.dump}.globals.sql"
  [ -f "$globals_path" ] || globals_path=""

  local db user password
  db="$(_dbbackup_env_get_kv "$env_file" "POSTGRES_DB" 2>/dev/null || true)"
  user="$(_dbbackup_env_get_kv "$env_file" "POSTGRES_USER" 2>/dev/null || true)"
  password="$(_dbbackup_env_get_kv "$env_file" "POSTGRES_PASSWORD" 2>/dev/null || true)"
  [ -z "${db:-}" ] && db="postgres"
  [ -z "${user:-}" ] && user="postgres"

  if [ -z "${password:-}" ]; then
    tgdb_fail "找不到 POSTGRES_PASSWORD：$env_file" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  # 避免 SQL 注入/引號問題：先限制名稱格式
  if [[ ! "$db" =~ ^[A-Za-z0-9_]+$ ]] || [[ ! "$user" =~ ^[A-Za-z0-9_]+$ ]]; then
    tgdb_fail "偵測到資料庫名稱/帳號含特殊字元（db=$db, user=$user）。此功能暫不支援自動覆蓋，請改用手動還原。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  echo "⚠️ 重要提醒：此操作會『覆蓋』目標資料庫內容。"
  echo " - 目標容器：$container_name"
  echo " - 目標資料庫：$db"
  echo " - 匯入檔案：$dump_path"
  if [ -n "${globals_path:-}" ]; then
    echo " - globals：$globals_path"
  fi
  echo "建議：先停止所有會連線到此 DB 的上游服務，避免匯入期間被寫入。"

  if [ "${assume_yes:-0}" != "1" ]; then
    if ! ui_confirm_yn "確認繼續覆蓋還原嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
      local rc=$?
      [ "$rc" -eq 2 ] && return 2
      return 0
    fi
  fi

  echo "⏳ 等待 PostgreSQL 服務就緒（最多 ${DBBACKUP_DB_READY_TIMEOUT} 秒）..."
  if ! _dbbackup_wait_postgres_ready "$container_name" "$user" "$password"; then
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local ts tmp_dump
  ts="$(date +%Y%m%d-%H%M%S)"
  tmp_dump="/tmp/tgdb_import_${ts}.dump"
  local cp_out="" cp_rc=0
  cp_out="$(podman cp "$dump_path" "${container_name}:${tmp_dump}" 2>&1)" || cp_rc=$?
  if [ "$cp_rc" -ne 0 ]; then
    tgdb_fail "無法把檔案複製進容器：$container_name（$cp_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  if [ -n "${globals_path:-}" ]; then
    local tmp_globals="/tmp/tgdb_import_globals_${ts}.sql"
    if podman cp "$globals_path" "${container_name}:${tmp_globals}" 2>/dev/null; then
      podman exec -e TGDB_USER="$user" -e TGDB_PASS="$password" -e TGDB_FILE="$tmp_globals" \
        "$container_name" sh -c 'set -eu; export PGPASSWORD="$TGDB_PASS"; psql -h 127.0.0.1 -p 5432 -U "$TGDB_USER" -d postgres -v ON_ERROR_STOP=1 -f "$TGDB_FILE"' 2>/dev/null || \
        tgdb_warn "globals 匯入失敗（已嘗試，但不影響後續 DB 匯入）。"
      podman exec "$container_name" rm -f "$tmp_globals" >/dev/null 2>&1 || true
    else
      tgdb_warn "globals 檔案複製失敗（已略過）。"
    fi
  fi

  # 強制切斷連線後重建資料庫，確保是「覆蓋」的乾淨狀態
  local rebuild_out="" rebuild_rc=0
  rebuild_out="$(podman exec -e TGDB_DB="$db" -e TGDB_USER="$user" -e TGDB_PASS="$password" \
    "$container_name" sh -c 'set -eu; export PGPASSWORD="$TGDB_PASS"; psql -h 127.0.0.1 -p 5432 -U "$TGDB_USER" -d postgres -v ON_ERROR_STOP=1 \
      -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='\''$TGDB_DB'\'' AND pid<>pg_backend_pid();" \
      -c "DROP DATABASE IF EXISTS \"${TGDB_DB}\";" \
      -c "CREATE DATABASE \"${TGDB_DB}\";"' 2>&1)" || rebuild_rc=$?
  if [ "$rebuild_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_dump" >/dev/null 2>&1 || true
    tgdb_fail "重建資料庫失敗：$db（$rebuild_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local restore_out="" restore_rc=0
  restore_out="$(podman exec -e TGDB_DB="$db" -e TGDB_USER="$user" -e TGDB_PASS="$password" -e TGDB_FILE="$tmp_dump" \
    "$container_name" sh -c 'set -eu; export PGPASSWORD="$TGDB_PASS"; pg_restore -h 127.0.0.1 -p 5432 -U "$TGDB_USER" -d "$TGDB_DB" --no-owner --no-acl "$TGDB_FILE"' 2>&1)" || restore_rc=$?
  if [ "$restore_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_dump" >/dev/null 2>&1 || true
    tgdb_fail "匯入失敗：$container_name（$restore_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  podman exec "$container_name" rm -f "$tmp_dump" >/dev/null 2>&1 || true

  echo "✅ 匯入完成：已覆蓋還原 $db"
  echo "ℹ️ 建議：啟動上游服務前先做基本查詢/健康檢查確認資料完整。"
  _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
  return 0
}
