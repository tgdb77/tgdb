#!/bin/bash

# 數據庫管理：定時備份選單
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_TIMERS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_TIMERS_LOADED=1

dbbackup_all_timer_get_schedule() {
  _dbbackup_all_timer_oncalendar_get
}

dbbackup_all_timer_set_schedule() {
  dbbackup_all_cmd_set_oncalendar "$@"
}

dbbackup_all_timer_status_extra() {
  _dbbackup_all_status_extra
}

dbbackup_all_timer_special_menu() {
  local include_globals="0"
  local rc=0

  if ui_confirm_yn "是否同時匯出 PostgreSQL roles/權限（globals-only）？(y/N，預設 N，輸入 0 取消): " "N"; then
    include_globals="1"
  else
    rc=$?
    [ "$rc" -eq 2 ] && return 0
  fi

  dbbackup_all_timer_set_include_globals "$include_globals" || return 1
  ui_pause "按任意鍵返回..."
}

tgdb_timer_define_dbbackup_all_task() {
  # shellcheck disable=SC2034 # 供共用選單/回呼跨檔案讀取
  {
    TGDB_TIMER_TASK_ID="dbbackup_all"
    TGDB_TIMER_TASK_TITLE="數據庫批次匯出"
    TGDB_TIMER_TIMER_UNIT="$DBBACKUP_ALL_TIMER"
    TGDB_TIMER_SERVICE_UNIT="$DBBACKUP_ALL_SERVICE"
    TGDB_TIMER_SCHEDULE_MODE="oncalendar"
    TGDB_TIMER_SCHEDULE_KEY="OnCalendar"
    TGDB_TIMER_SCHEDULE_HINT="此任務會自動偵測全部 DB 實例並批次匯出。"
    TGDB_TIMER_SPECIAL_LABEL="設定 PostgreSQL roles/權限匯出（特殊功能）"
    TGDB_TIMER_ENABLE_CB="dbbackup_all_cmd_enable_timer"
    TGDB_TIMER_DISABLE_CB="dbbackup_all_cmd_disable_timer"
    TGDB_TIMER_REMOVE_CB="dbbackup_all_cmd_remove_timer"
    TGDB_TIMER_GET_SCHEDULE_CB="dbbackup_all_timer_get_schedule"
    TGDB_TIMER_SET_SCHEDULE_CB="dbbackup_all_timer_set_schedule"
    TGDB_TIMER_RUN_NOW_CB="dbbackup_all_cmd_export_all"
    TGDB_TIMER_STATUS_EXTRA_CB="dbbackup_all_timer_status_extra"
    TGDB_TIMER_SPECIAL_CB="dbbackup_all_timer_special_menu"
    TGDB_TIMER_HEALTHCHECKS_SUPPORTED="1"
    TGDB_TIMER_RUN_VIA_RUNNER="1"
    TGDB_TIMER_CONTEXT_KIND="built_in"
    TGDB_TIMER_CONTEXT_ID="dbbackup_all"
  }
}

_dbadmin_dbbackup_timers_menu() {
  tgdb_timer_task_menu "dbbackup_all"
}
