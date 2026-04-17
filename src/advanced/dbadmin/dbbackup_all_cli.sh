#!/bin/bash

# 數據庫備份：批次 CLI（export-all / import-all-latest / timer）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DBBACKUP_ALL_CLI_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DBBACKUP_ALL_CLI_LOADED=1

DBBACKUP_ALL_SERVICE="tgdb-dbbackup-all.service"
DBBACKUP_ALL_TIMER="tgdb-dbbackup-all.timer"

_dbbackup_all_service_file() {
  tgdb_timer_unit_path "$DBBACKUP_ALL_SERVICE"
}

_dbbackup_all_write_user_unit() {
  tgdb_timer_write_user_unit "$1" "$2"
}

_dbbackup_all_timer_oncalendar_get() {
  tgdb_timer_schedule_get "$DBBACKUP_ALL_TIMER" "OnCalendar"
}

_dbbackup_all_include_globals_get() {
  local f
  f="$(_dbbackup_all_service_file)"
  [ -f "$f" ] || return 1
  awk -F= '/^Environment=TGDB_DBBACKUP_INCLUDE_GLOBALS=/{print $2; exit}' "$f" 2>/dev/null
}

dbbackup_all_timer_set_include_globals() {
  local include_globals="${1:-0}"
  local service_file

  case "$include_globals" in
    0|1)
      ;;
    *)
      tgdb_fail "globals-only 僅支援 0 或 1。" 2 || return $?
      ;;
  esac

  service_file="$(_dbbackup_all_service_file)"
  if [ ! -f "$service_file" ]; then
    tgdb_fail "尚未建立 $DBBACKUP_ALL_SERVICE，請先開啟任務。" 1 || return $?
  fi

  if grep -q '^Environment=TGDB_DBBACKUP_INCLUDE_GLOBALS=' "$service_file" 2>/dev/null; then
    sed -i "s|^Environment=TGDB_DBBACKUP_INCLUDE_GLOBALS=.*$|Environment=TGDB_DBBACKUP_INCLUDE_GLOBALS=$include_globals|" "$service_file"
  else
    printf 'Environment=TGDB_DBBACKUP_INCLUDE_GLOBALS=%s\n' "$include_globals" >>"$service_file"
  fi

  _systemctl_user_try daemon-reload || true
  echo "✅ 已更新 PostgreSQL roles/權限匯出設定：$include_globals"
}

_dbbackup_all_target_include_globals() {
  local include_globals=""

  if [ -n "${TGDB_DBBACKUP_INCLUDE_GLOBALS+x}" ]; then
    include_globals="${TGDB_DBBACKUP_INCLUDE_GLOBALS:-0}"
  else
    include_globals="$(_dbbackup_all_include_globals_get 2>/dev/null || true)"
  fi

  case "$include_globals" in
    0|1)
      ;;
    *)
      include_globals="0"
      ;;
  esac

  printf '%s\n' "$include_globals"
}

_dbbackup_all_write_units() {
  local sched="$1"
  local include_globals="$2"
  local runner_abs

  runner_abs="$(tgdb_timer_runner_script_path)"
  _dbbackup_all_write_user_unit "$DBBACKUP_ALL_SERVICE" "[Unit]\nDescription=TGDB DB Dump Backup (All Instances)\n\n[Service]\nType=oneshot\nEnvironment=TGDB_DBBACKUP_NONINTERACTIVE=1\nEnvironment=TGDB_DBBACKUP_INCLUDE_GLOBALS=$include_globals\nExecStart=/bin/bash \"$runner_abs\" run dbbackup_all timer\n"
  _dbbackup_all_write_user_unit "$DBBACKUP_ALL_TIMER" "[Unit]\nDescription=TGDB DB Dump Backup (All Instances)\n\n[Timer]\nOnCalendar=$sched\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"
}

_dbbackup_all_ensure_units() {
  local include_globals

  include_globals="$(_dbbackup_all_target_include_globals)"
  _dbbackup_all_write_units "daily" "$include_globals"
}

_dbbackup_all_status_extra() {
  local include_globals

  include_globals="$(_dbbackup_all_include_globals_get 2>/dev/null || true)"
  [ -z "${include_globals:-}" ] && include_globals="0"
  echo "匯出 PostgreSQL roles/權限：$include_globals"
}

dbbackup_all_cmd_export_all() {
  # 非互動模式：不要 pause/不要詢問。
  export TGDB_DBBACKUP_NONINTERACTIVE=1

  local include_globals="N"
  if [ "${TGDB_DBBACKUP_INCLUDE_GLOBALS:-0}" = "1" ]; then
    include_globals="Y"
  fi

  dbbackup_p_export_all_run "$include_globals" "0"
}

dbbackup_all_cmd_import_all_latest() {
  # 非互動模式：不要 pause/不要詢問。
  export TGDB_DBBACKUP_NONINTERACTIVE=1
  dbbackup_p_import_all_latest_run "0"
}

dbbackup_all_cmd_status() {
  tgdb_timer_print_status "$DBBACKUP_ALL_TIMER" "OnCalendar" "_dbbackup_all_status_extra"
}

dbbackup_all_cmd_setup_timer() {
  local freq="${1:-daily}"
  tgdb_timer_validate_named_frequency "$freq" || return $?

  local include_globals
  include_globals="$(_dbbackup_all_target_include_globals)"
  tgdb_timer_setup_managed "$DBBACKUP_ALL_TIMER" "_dbbackup_all_write_units" "$freq" "$include_globals" || return 1

  echo "✅ 已安裝並啟用：$DBBACKUP_ALL_TIMER（OnCalendar=$freq）"
  echo "提示：globals-only（PostgreSQL roles/權限）=$include_globals（可重新設定 timer 或手動調整 $(_dbbackup_all_service_file)）。"
  return 0
}

dbbackup_all_cmd_set_oncalendar() {
  local sched="$*"

  if [ -z "${sched:-}" ]; then
    tgdb_fail "用法：dbbackup-cli.sh set-oncalendar <OnCalendar>" 2 || return $?
  fi

  tgdb_timer_schedule_set "$DBBACKUP_ALL_TIMER" "OnCalendar" "$sched" || return 1
  echo "✅ 已更新 $DBBACKUP_ALL_TIMER 排程：$sched"
  return 0
}

dbbackup_all_cmd_enable_timer() {
  if tgdb_timer_enable_managed "$DBBACKUP_ALL_TIMER" "$DBBACKUP_ALL_SERVICE" "_dbbackup_all_ensure_units"; then
    echo "✅ 已開啟：$DBBACKUP_ALL_TIMER"
    return 0
  fi

  tgdb_warn "無法直接開啟 $DBBACKUP_ALL_TIMER，已保留現有設定檔。"
  return 1
}

dbbackup_all_cmd_disable_timer() {
  if ! tgdb_timer_unit_exists "$DBBACKUP_ALL_TIMER" && ! tgdb_timer_unit_exists "$DBBACKUP_ALL_SERVICE"; then
    tgdb_warn "尚未建立定時備份任務，無需關閉。"
    return 0
  fi

  tgdb_timer_disable_units "$DBBACKUP_ALL_TIMER" "$DBBACKUP_ALL_SERVICE" || true
  echo "✅ 已關閉：$DBBACKUP_ALL_TIMER（保留設定檔）"
  return 0
}

dbbackup_all_cmd_remove_timer() {
  tgdb_timer_remove_units "$DBBACKUP_ALL_TIMER" "$DBBACKUP_ALL_SERVICE" || true
  echo "✅ 已移除：$DBBACKUP_ALL_TIMER / $DBBACKUP_ALL_SERVICE"
  return 0
}

dbbackup_all_usage() {
  cat <<USAGE
用法: dbbackup-cli.sh <export-all|import-all-latest|status|setup-timer|set-oncalendar|enable-timer|disable-timer|remove-timer>

  export-all             自動偵測所有 DB 實例並匯出（非互動模式）
  import-all-latest      自動偵測所有 DB 實例並匯入最新備份（非互動模式）
  status                 顯示 timer 狀態
  setup-timer <freq>     設定定期備份：daily|weekly|monthly
  set-oncalendar <expr>  更新 timer 的 OnCalendar（允許含空白）
  enable-timer           開啟既有 timer；若不存在則建立 daily
  disable-timer          關閉 timer，但保留設定檔
  remove-timer           移除定期備份 timer

環境變數：
  TGDB_DBBACKUP_INCLUDE_GLOBALS=1  匯出 PostgreSQL 時同時匯出 globals-only
USAGE
}

dbbackup_all_main() {
  local subcmd="${1:-}"
  case "$subcmd" in
    export-all) shift; dbbackup_all_cmd_export_all "$@" ;;
    import-all-latest) shift; dbbackup_all_cmd_import_all_latest "$@" ;;
    status) shift; dbbackup_all_cmd_status "$@" ;;
    setup-timer) shift; dbbackup_all_cmd_setup_timer "$@" ;;
    set-oncalendar) shift; dbbackup_all_cmd_set_oncalendar "$@" ;;
    enable-timer) shift; dbbackup_all_cmd_enable_timer "$@" ;;
    disable-timer) shift; dbbackup_all_cmd_disable_timer "$@" ;;
    remove-timer) shift; dbbackup_all_cmd_remove_timer "$@" ;;
    *) dbbackup_all_usage; return 1 ;;
  esac
}
