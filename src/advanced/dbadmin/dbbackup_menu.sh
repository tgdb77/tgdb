#!/bin/bash

# 數據庫備份：互動式選單入口
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DBBACKUP_MENU_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DBBACKUP_MENU_LOADED=1

dbbackup_p_export_menu() {
  _dbbackup_require_interactive || return $?
  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法使用匯入/匯出。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local db_type rc=0
  _dbbackup_pick_db_type db_type || rc=$?
  [ "$rc" -eq 2 ] && return 0
  [ "$rc" -ne 0 ] && return 1

  local picked="" picked_rc=0
  _dbbackup_pick_db_endpoint "$db_type" picked || picked_rc=$?
  [ "$picked_rc" -eq 2 ] && return 0
  [ "$picked_rc" -ne 0 ] && return 1

  local _ container_name env_file instance_dir unit_path
  IFS='|' read -r _ container_name env_file instance_dir unit_path <<< "$picked"

  case "$db_type" in
    postgres)
      _dbbackup_postgres_export "$container_name" "$env_file" "$instance_dir"
      ;;
    redis)
      _dbbackup_redis_export "$container_name" "$env_file" "$instance_dir"
      ;;
    mysql)
      _dbbackup_mysql_export "$container_name" "$env_file" "$instance_dir"
      ;;
    mongo)
      _dbbackup_mongo_export "$container_name" "$env_file" "$instance_dir"
      ;;
  esac
}

dbbackup_p_import_menu() {
  _dbbackup_require_interactive || return $?
  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法使用匯入/匯出。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local db_type rc=0
  _dbbackup_pick_db_type db_type || rc=$?
  [ "$rc" -eq 2 ] && return 0
  [ "$rc" -ne 0 ] && return 1

  local picked="" picked_rc=0
  _dbbackup_pick_db_endpoint "$db_type" picked || picked_rc=$?
  [ "$picked_rc" -eq 2 ] && return 0
  [ "$picked_rc" -ne 0 ] && return 1

  local _ container_name env_file instance_dir unit_path
  IFS='|' read -r _ container_name env_file instance_dir unit_path <<< "$picked"

  case "$db_type" in
    postgres)
      _dbbackup_postgres_import_overwrite "$container_name" "$env_file" "$instance_dir"
      ;;
    redis)
      _dbbackup_redis_import_overwrite "$container_name" "$env_file" "$instance_dir" "$unit_path"
      ;;
    mysql)
      _dbbackup_mysql_import_overwrite "$container_name" "$env_file" "$instance_dir"
      ;;
    mongo)
      _dbbackup_mongo_import_overwrite "$container_name" "$env_file" "$instance_dir"
      ;;
  esac
}
