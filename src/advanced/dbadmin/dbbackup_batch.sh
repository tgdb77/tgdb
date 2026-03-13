#!/bin/bash

# 數據庫備份：批次流程（全部匯出/最新匯入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DBBACKUP_BATCH_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DBBACKUP_BATCH_LOADED=1

_dbbackup_latest_backup_file() {
  local dir="$1" ext="$2"
  [ -d "$dir" ] || return 1
  [ -n "${ext:-}" ] || return 1
  _dbbackup_list_backups_newest_first "$dir" "$ext" | head -n 1 | awk 'NF{print; exit}'
}

dbbackup_p_export_all_run() {
  local include_globals="${1:-N}" want_pause_each="${2:-0}"
  include_globals="$(_dbbackup_trim_ws "$include_globals")"
  case "$include_globals" in
    Y|y) include_globals="Y" ;;
    *) include_globals="N" ;;
  esac

  local -a pg_eps=() r_eps=() m_eps=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && pg_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints postgres)
  while IFS= read -r line; do
    [ -n "$line" ] && r_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints redis)
  while IFS= read -r line; do
    [ -n "$line" ] && m_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints mysql)

  if [ ${#pg_eps[@]} -eq 0 ] && [ ${#r_eps[@]} -eq 0 ] && [ ${#m_eps[@]} -eq 0 ]; then
    tgdb_fail "找不到任何可用的 DB 目標（請確認 Label=tgdb_db=postgres/redis/mysql 與掛載/環境檔）。" 1 || true
    _dbbackup_ui_pause_if 1 "按任意鍵返回..."
    return 1
  fi

  local ok=0 fail=0
  if [ ${#pg_eps[@]} -gt 0 ]; then
    echo "=== PostgreSQL：共 ${#pg_eps[@]} 個目標 ==="
    local display container_name env_file instance_dir _
    for line in "${pg_eps[@]}"; do
      IFS='|' read -r display container_name env_file instance_dir _ <<< "$line"
      echo "▶ 匯出：$display"
      if _dbbackup_postgres_export "$container_name" "$env_file" "$instance_dir" "$want_pause_each" "$include_globals"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  if [ ${#r_eps[@]} -gt 0 ]; then
    echo "=== Redis：共 ${#r_eps[@]} 個目標 ==="
    local display2 container_name2 env_file2 instance_dir2 unit_path2
    for line in "${r_eps[@]}"; do
      IFS='|' read -r display2 container_name2 env_file2 instance_dir2 unit_path2 <<< "$line"
      echo "▶ 匯出：$display2"
      if _dbbackup_redis_export "$container_name2" "$env_file2" "$instance_dir2" "$want_pause_each"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  if [ ${#m_eps[@]} -gt 0 ]; then
    echo "=== MySQL：共 ${#m_eps[@]} 個目標 ==="
    local display3 container_name3 env_file3 instance_dir3
    for line in "${m_eps[@]}"; do
      IFS='|' read -r display3 container_name3 env_file3 instance_dir3 _ <<< "$line"
      echo "▶ 匯出：$display3"
      if _dbbackup_mysql_export "$container_name3" "$env_file3" "$instance_dir3" "$want_pause_each"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  echo "----------------------------------"
  echo "批次匯出完成：成功=$ok / 失敗=$fail"
  [ "$fail" -eq 0 ] && return 0
  return 1
}

dbbackup_p_import_all_latest_run() {
  local want_pause_each="${1:-0}"

  local -a pg_eps=() r_eps=() m_eps=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && pg_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints postgres)
  while IFS= read -r line; do
    [ -n "$line" ] && r_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints redis)
  while IFS= read -r line; do
    [ -n "$line" ] && m_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints mysql)

  if [ ${#pg_eps[@]} -eq 0 ] && [ ${#r_eps[@]} -eq 0 ] && [ ${#m_eps[@]} -eq 0 ]; then
    echo "ℹ️ 未偵測到可匯入的 DB 目標（略過）。"
    return 0
  fi

  local ok=0 fail=0 skip=0
  if [ ${#pg_eps[@]} -gt 0 ]; then
    echo "=== PostgreSQL：開始批次匯入（latest） ==="
    local display container_name env_file instance_dir _ dump_dir dump_path
    for line in "${pg_eps[@]}"; do
      IFS='|' read -r display container_name env_file instance_dir _ <<< "$line"
      dump_dir="$(_dbbackup_project_backup_dir "$instance_dir" "postgres")"
      dump_path="$(_dbbackup_latest_backup_file "$dump_dir" "dump" 2>/dev/null || true)"
      if [ -z "${dump_path:-}" ]; then
        echo "⏭ 略過：$display（尚無備份檔）"
        skip=$((skip + 1))
        continue
      fi
      echo "▶ 匯入：$display（$(basename "$dump_path")）"
      if _dbbackup_postgres_import_overwrite "$container_name" "$env_file" "$instance_dir" "$want_pause_each" "$dump_path" "1"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  if [ ${#r_eps[@]} -gt 0 ]; then
    echo "=== Redis：開始批次匯入（latest） ==="
    local display2 container_name2 env_file2 instance_dir2 _ rdb_dir rdb_path
    for line in "${r_eps[@]}"; do
      IFS='|' read -r display2 container_name2 env_file2 instance_dir2 _ <<< "$line"
      rdb_dir="$(_dbbackup_project_backup_dir "$instance_dir2" "redis")"
      rdb_path="$(_dbbackup_latest_backup_file "$rdb_dir" "rdb" 2>/dev/null || true)"
      if [ -z "${rdb_path:-}" ]; then
        echo "⏭ 略過：$display2（尚無備份檔）"
        skip=$((skip + 1))
        continue
      fi
      echo "▶ 匯入：$display2（$(basename "$rdb_path")）"
      if _dbbackup_redis_import_overwrite "$container_name2" "$env_file2" "$instance_dir2" "$unit_path2" "$want_pause_each" "$rdb_path" "1"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  if [ ${#m_eps[@]} -gt 0 ]; then
    echo "=== MySQL：開始批次匯入（latest） ==="
    local display3 container_name3 env_file3 instance_dir3 sql_dir sql_path
    for line in "${m_eps[@]}"; do
      IFS='|' read -r display3 container_name3 env_file3 instance_dir3 _ <<< "$line"
      sql_dir="$(_dbbackup_project_backup_dir "$instance_dir3" "mysql")"
      sql_path="$(_dbbackup_latest_backup_file "$sql_dir" "sql" 2>/dev/null || true)"
      if [ -z "${sql_path:-}" ]; then
        echo "⏭ 略過：$display3（尚無備份檔）"
        skip=$((skip + 1))
        continue
      fi
      echo "▶ 匯入：$display3（$(basename "$sql_path")）"
      if _dbbackup_mysql_import_overwrite "$container_name3" "$env_file3" "$instance_dir3" "$want_pause_each" "$sql_path" "1"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  echo "----------------------------------"
  echo "批次匯入完成：成功=$ok / 失敗=$fail / 略過=$skip"
  [ "$fail" -eq 0 ] && return 0
  return 1
}

dbbackup_p_export_all_menu() {
  _dbbackup_require_interactive || return $?
  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法使用匯入/匯出。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local include_globals="N"
  if ui_confirm_yn "批次匯出：是否同時匯出 PostgreSQL roles/權限（globals-only）？(y/N，預設 N，輸入 0 取消): " "N"; then
    include_globals="Y"
  else
    local rc=$?
    [ "$rc" -eq 2 ] && return 0
  fi

  clear
  echo "⚠️ 批次匯出：將自動偵測所有 DB 實例並匯出。"
  echo " - PostgreSQL globals-only：$include_globals"
  if ! ui_confirm_yn "確認開始批次匯出嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    local rc2=$?
    [ "$rc2" -eq 2 ] && return 0
    return 0
  fi

  clear
  dbbackup_p_export_all_run "$include_globals" "0" || true
  ui_pause "按任意鍵返回..."
  return 0
}

dbbackup_p_import_all_latest_menu() {
  _dbbackup_require_interactive || return $?
  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法使用匯入/匯出。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local -a pg_eps=() r_eps=() m_eps=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && pg_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints postgres)
  while IFS= read -r line; do
    [ -n "$line" ] && r_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints redis)
  while IFS= read -r line; do
    [ -n "$line" ] && m_eps+=("$line")
  done < <(_dbbackup_find_db_endpoints mysql)

  if [ ${#pg_eps[@]} -eq 0 ] && [ ${#r_eps[@]} -eq 0 ] && [ ${#m_eps[@]} -eq 0 ]; then
    tgdb_fail "找不到任何可用的 DB 目標（請確認 Label=tgdb_db=postgres/redis/mysql 與掛載/環境檔）。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  clear
  echo "⚠️⚠️⚠️ 批次匯入（覆蓋還原）⚠️⚠️⚠️"
  echo "此操作會："
  echo " - 自動偵測所有 DB 實例"
  echo " - 每個實例使用『最新』備份檔覆蓋還原"
  echo "強烈建議：先停止所有上游服務。"
  echo "----------------------------------"
  echo "偵測到：PostgreSQL=${#pg_eps[@]} / Redis=${#r_eps[@]} / MySQL=${#m_eps[@]}"
  echo "----------------------------------"
  echo "請輸入 YES 確認繼續（輸入 0 取消）："
  local confirm
  read -r -e -p "> " confirm
  if [ "$confirm" = "0" ]; then
    echo "操作已取消。"
    sleep 1
    return 0
  fi
  if [ "$confirm" != "YES" ]; then
    tgdb_warn "未輸入 YES，已取消。"
    ui_pause "按任意鍵返回..."
    return 0
  fi

  local ok=0 fail=0 skip=0
  if [ ${#pg_eps[@]} -gt 0 ]; then
    echo "=== PostgreSQL：開始批次匯入 ==="
    local display container_name env_file instance_dir _ dump_dir dump_path
    for line in "${pg_eps[@]}"; do
      IFS='|' read -r display container_name env_file instance_dir _ <<< "$line"
      dump_dir="$(_dbbackup_project_backup_dir "$instance_dir" "postgres")"
      dump_path="$(_dbbackup_latest_backup_file "$dump_dir" "dump" 2>/dev/null || true)"
      if [ -z "${dump_path:-}" ]; then
        echo "⏭ 略過：$display（尚無備份檔）"
        skip=$((skip + 1))
        continue
      fi
      echo "▶ 匯入：$display（$(basename "$dump_path")）"
      if _dbbackup_postgres_import_overwrite "$container_name" "$env_file" "$instance_dir" "0" "$dump_path" "1"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  if [ ${#r_eps[@]} -gt 0 ]; then
    echo "=== Redis：開始批次匯入 ==="
    local display2 container_name2 env_file2 instance_dir2 unit_path2 rdb_dir rdb_path
    for line in "${r_eps[@]}"; do
      IFS='|' read -r display2 container_name2 env_file2 instance_dir2 unit_path2 <<< "$line"
      rdb_dir="$(_dbbackup_project_backup_dir "$instance_dir2" "redis")"
      rdb_path="$(_dbbackup_latest_backup_file "$rdb_dir" "rdb" 2>/dev/null || true)"
      if [ -z "${rdb_path:-}" ]; then
        echo "⏭ 略過：$display2（尚無備份檔）"
        skip=$((skip + 1))
        continue
      fi
      echo "▶ 匯入：$display2（$(basename "$rdb_path")）"
      if _dbbackup_redis_import_overwrite "$container_name2" "$env_file2" "$instance_dir2" "$unit_path2" "0" "$rdb_path" "1"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  if [ ${#m_eps[@]} -gt 0 ]; then
    echo "=== MySQL：開始批次匯入 ==="
    local display3 container_name3 env_file3 instance_dir3 sql_dir sql_path
    for line in "${m_eps[@]}"; do
      IFS='|' read -r display3 container_name3 env_file3 instance_dir3 _ <<< "$line"
      sql_dir="$(_dbbackup_project_backup_dir "$instance_dir3" "mysql")"
      sql_path="$(_dbbackup_latest_backup_file "$sql_dir" "sql" 2>/dev/null || true)"
      if [ -z "${sql_path:-}" ]; then
        echo "⏭ 略過：$display3（尚無備份檔）"
        skip=$((skip + 1))
        continue
      fi
      echo "▶ 匯入：$display3（$(basename "$sql_path")）"
      if _dbbackup_mysql_import_overwrite "$container_name3" "$env_file3" "$instance_dir3" "0" "$sql_path" "1"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    done
  fi

  echo "----------------------------------"
  echo "批次匯入完成：成功=$ok / 失敗=$fail / 略過=$skip"
  ui_pause "按任意鍵返回..."
  return 0
}
