#!/bin/bash

# 數據庫備份：MySQL 匯出/匯入
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DBBACKUP_MYSQL_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DBBACKUP_MYSQL_LOADED=1

_dbbackup_mysql_export() {
  local container_name="$1" env_file="$2" instance_dir="$3" want_pause="${4:-1}"
  [ -n "$container_name" ] || return 1
  [ -f "$env_file" ] || return 1
  [ -n "${instance_dir:-}" ] || instance_dir="$(dirname "$env_file" 2>/dev/null || echo "")"

  _dbbackup_ensure_container_running "$container_name" || {
    local rc=$?
    _dbbackup_pause_on_error "$rc" || true
    return "$rc"
  }

  if ! podman exec "$container_name" sh -c 'command -v mysqldump >/dev/null 2>&1' 2>/dev/null; then
    tgdb_fail "容器內找不到 mysqldump：$container_name（此功能暫不支援該映像）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local db user user_password root_password dump_user dump_password auth_source
  db="$(_dbbackup_env_get_kv "$env_file" "MYSQL_DATABASE" 2>/dev/null || true)"
  user="$(_dbbackup_env_get_kv "$env_file" "MYSQL_USER" 2>/dev/null || true)"
  user_password="$(_dbbackup_env_get_kv "$env_file" "MYSQL_PASSWORD" 2>/dev/null || true)"
  root_password="$(_dbbackup_env_get_kv "$env_file" "MYSQL_ROOT_PASSWORD" 2>/dev/null || true)"
  [ -z "${db:-}" ] && db="mysql"

  dump_user="$user"
  dump_password="$user_password"
  auth_source="MYSQL_USER/MYSQL_PASSWORD"
  if [ -z "${dump_user:-}" ] || [ -z "${dump_password:-}" ]; then
    if [ -n "${root_password:-}" ]; then
      dump_user="root"
      dump_password="$root_password"
      auth_source="MYSQL_ROOT_PASSWORD"
      tgdb_warn "找不到完整的 MYSQL_USER/MYSQL_PASSWORD，改用 root 帳號匯出。"
    else
      tgdb_fail "找不到可用的 MySQL 帳密：$env_file（需要 MYSQL_USER+MYSQL_PASSWORD 或 MYSQL_ROOT_PASSWORD）。" 1 || true
      _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
      return 1
    fi
  fi

  local out_dir ts out_sql out_meta
  out_dir="$(_dbbackup_project_backup_dir "$instance_dir" "mysql")" || return 1
  _dbbackup_ensure_dir_writable "$out_dir" || { _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."; return 1; }
  chmod 700 "$out_dir" 2>/dev/null || true
  echo "輸出目錄：$out_dir"
  echo "連線資訊：db=$db / user=$dump_user"
  echo "設定檔：$env_file"

  ts="$(date +%Y%m%d-%H%M%S)"
  out_sql="$out_dir/${ts}.sql"
  out_meta="$out_dir/${ts}.meta.conf"

  local tmp_sql="/tmp/tgdb_${ts}.sql"
  local dump_out="" dump_rc=0
  dump_out="$(podman exec -e TGDB_DB="$db" -e TGDB_USER="$dump_user" -e TGDB_PASS="$dump_password" -e TGDB_OUT="$tmp_sql" \
    "$container_name" sh -c 'set -eu; export MYSQL_PWD="$TGDB_PASS"; mysqldump -h 127.0.0.1 -P 3306 -u"$TGDB_USER" --single-transaction --quick --routines --events --triggers --no-tablespaces --set-gtid-purged=OFF --databases "$TGDB_DB" >"$TGDB_OUT"' 2>&1)" || dump_rc=$?
  if [ "$dump_rc" -ne 0 ]; then
    tgdb_fail "匯出失敗：$container_name（$dump_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local cp_out="" cp_rc=0
  local tmp_out_sql="${out_sql}.tmp"
  rm -f -- "$tmp_out_sql" 2>/dev/null || true
  cp_out="$(podman cp "${container_name}:${tmp_sql}" "$tmp_out_sql" 2>&1)" || cp_rc=$?
  if [ "$cp_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_sql" >/dev/null 2>&1 || true
    tgdb_fail "無法從容器取回檔案：$container_name:$tmp_sql（$cp_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi
  podman exec "$container_name" rm -f "$tmp_sql" >/dev/null 2>&1 || true
  if ! mv -f -- "$tmp_out_sql" "$out_sql" 2>/dev/null; then
    rm -f -- "$tmp_out_sql" 2>/dev/null || true
    tgdb_fail "匯出檔案寫入失敗（無法原子改名）：$tmp_out_sql -> $out_sql" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  {
    echo "created_at=$ts"
    echo "db_type=mysql"
    echo "container_name=$container_name"
    echo "env_file=$env_file"
    echo "db_name=$db"
    echo "dump_user=$dump_user"
    echo "auth_source=$auth_source"
    echo "format=mysqldump_sql"
  } >"$out_meta" 2>/dev/null || true
  chmod 600 "$out_meta" 2>/dev/null || true

  _dbbackup_prune_old_backups "$out_dir" "$(_dbbackup_max_keep_get)" "sql" || true

  echo "✅ 匯出完成：$out_sql"
  echo " - meta：$out_meta"
  _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
  return 0
}

_dbbackup_mysql_import_overwrite() {
  local container_name="$1" env_file="$2" instance_dir="$3" want_pause="${4:-1}" forced_sql_path="${5:-}" assume_yes="${6:-0}"
  [ -n "$container_name" ] || return 1
  [ -f "$env_file" ] || return 1
  [ -n "${instance_dir:-}" ] || instance_dir="$(dirname "$env_file" 2>/dev/null || echo "")"

  _dbbackup_ensure_container_running "$container_name" || {
    local rc=$?
    _dbbackup_pause_on_error "$rc" || true
    return "$rc"
  }

  if ! podman exec "$container_name" sh -c 'command -v mysql >/dev/null 2>&1' 2>/dev/null; then
    tgdb_fail "容器內缺少 mysql 指令：$container_name（此功能暫不支援該映像）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local sql_dir sql_path
  sql_dir="$(_dbbackup_project_backup_dir "$instance_dir" "mysql")" || return 1
  forced_sql_path="$(_dbbackup_trim_ws "${forced_sql_path:-}")"
  if [ -n "${forced_sql_path:-}" ]; then
    sql_path="$forced_sql_path"
    if [ ! -f "$sql_path" ]; then
      tgdb_fail "找不到備份檔：$sql_path" 1 || true
      _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
      return 1
    fi
  else
    _dbbackup_pick_existing_backup_file "$sql_dir" "sql" sql_path || return $?
  fi

  local db user user_password root_password restore_user restore_password auth_source
  db="$(_dbbackup_env_get_kv "$env_file" "MYSQL_DATABASE" 2>/dev/null || true)"
  user="$(_dbbackup_env_get_kv "$env_file" "MYSQL_USER" 2>/dev/null || true)"
  user_password="$(_dbbackup_env_get_kv "$env_file" "MYSQL_PASSWORD" 2>/dev/null || true)"
  root_password="$(_dbbackup_env_get_kv "$env_file" "MYSQL_ROOT_PASSWORD" 2>/dev/null || true)"
  [ -z "${db:-}" ] && db="mysql"

  restore_user=""
  restore_password=""
  auth_source=""
  if [ -n "${root_password:-}" ]; then
    restore_user="root"
    restore_password="$root_password"
    auth_source="MYSQL_ROOT_PASSWORD"
  elif [ -n "${user:-}" ] && [ -n "${user_password:-}" ]; then
    restore_user="$user"
    restore_password="$user_password"
    auth_source="MYSQL_USER/MYSQL_PASSWORD"
  else
    tgdb_fail "找不到可用的 MySQL 還原帳密：$env_file（需要 MYSQL_ROOT_PASSWORD，或至少 MYSQL_USER+MYSQL_PASSWORD）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  if [[ ! "$db" =~ ^[A-Za-z0-9_]+$ ]]; then
    tgdb_fail "偵測到資料庫名稱含特殊字元（db=$db）。此功能暫不支援自動覆蓋，請改用手動還原。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  echo "⚠️ 重要提醒：此操作會『覆蓋』目標資料庫內容。"
  echo " - 目標容器：$container_name"
  echo " - 目標資料庫：$db"
  echo " - 還原帳號來源：$auth_source（user=$restore_user）"
  echo " - 匯入檔案：$sql_path"
  echo "建議：先停止所有會連線到此 DB 的上游服務，避免匯入期間被寫入。"

  if [ "${assume_yes:-0}" != "1" ]; then
    if ! ui_confirm_yn "確認繼續覆蓋還原嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
      local rc=$?
      [ "$rc" -eq 2 ] && return 2
      return 0
    fi
  fi

  echo "⏳ 等待 MySQL 服務就緒（最多 ${DBBACKUP_DB_READY_TIMEOUT} 秒）..."
  if ! _dbbackup_wait_mysql_ready "$container_name" "$restore_user" "$restore_password"; then
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local ts tmp_sql
  ts="$(date +%Y%m%d-%H%M%S)"
  tmp_sql="/tmp/tgdb_import_${ts}.sql"
  local cp_out="" cp_rc=0
  cp_out="$(podman cp "$sql_path" "${container_name}:${tmp_sql}" 2>&1)" || cp_rc=$?
  if [ "$cp_rc" -ne 0 ]; then
    tgdb_fail "無法把檔案複製進容器：$container_name（$cp_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local rebuild_out="" rebuild_rc=0
  rebuild_out="$(podman exec -e TGDB_DB="$db" -e TGDB_USER="$restore_user" -e TGDB_PASS="$restore_password" \
    "$container_name" sh -c 'set -eu; export MYSQL_PWD="$TGDB_PASS"; mysql -h 127.0.0.1 -P 3306 -u"$TGDB_USER" -e "DROP DATABASE IF EXISTS \`$TGDB_DB\`; CREATE DATABASE \`$TGDB_DB\`;"' 2>&1)" || rebuild_rc=$?
  if [ "$rebuild_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_sql" >/dev/null 2>&1 || true
    tgdb_fail "重建資料庫失敗：$db（$rebuild_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local restore_out="" restore_rc=0
  restore_out="$(podman exec -e TGDB_DB="$db" -e TGDB_USER="$restore_user" -e TGDB_PASS="$restore_password" -e TGDB_FILE="$tmp_sql" \
    "$container_name" sh -c 'set -eu; export MYSQL_PWD="$TGDB_PASS"; mysql -h 127.0.0.1 -P 3306 -u"$TGDB_USER" "$TGDB_DB" <"$TGDB_FILE"' 2>&1)" || restore_rc=$?
  if [ "$restore_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_sql" >/dev/null 2>&1 || true
    tgdb_fail "匯入失敗：$container_name（$restore_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  podman exec "$container_name" rm -f "$tmp_sql" >/dev/null 2>&1 || true

  echo "✅ 匯入完成：已覆蓋還原 $db"
  echo "ℹ️ 建議：啟動上游服務前先做基本查詢/健康檢查確認資料完整。"
  _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
  return 0
}
