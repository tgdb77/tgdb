#!/bin/bash

# Kopia 管理：忽略檔與排程選單
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_MENU_TIMERS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_MENU_TIMERS_LOADED=1

kopia_p_edit_ignore_file() {
  _kopia_require_interactive || return $?

  if ! ensure_editor; then
    tgdb_fail "找不到可用編輯器（請安裝 nano/vim/vi 或設定 EDITOR）。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local runner
  runner="$(_kopia_runner_script)"
  if [ ! -f "$runner" ]; then
    tgdb_fail "找不到腳本：$runner" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  # 確保檔案存在（第一次先生成）
  bash "$runner" generate-ignore >/dev/null 2>&1 || true

  local ignore_file
  ignore_file="$TGDB_DIR/.kopiaignore"
  echo "→ 啟動編輯器: $EDITOR"
  echo "檔案：$ignore_file"
  "$EDITOR" "$ignore_file"
  return 0
}

_kopia_timer_runner_or_fail() {
  local runner

  runner="$(_kopia_runner_script)"
  if [ ! -f "$runner" ]; then
    tgdb_fail "找不到腳本：$runner" 1 || return $?
  fi

  printf '%s\n' "$runner"
}

_kopia_timer_cli_call() {
  local runner

  runner="$(_kopia_timer_runner_or_fail)" || return 1
  bash "$runner" "$@"
}

kopia_timer_get_schedule() {
  tgdb_timer_schedule_get "tgdb-kopia-backup.timer" "OnCalendar"
}

kopia_timer_set_schedule() {
  _kopia_timer_cli_call set-oncalendar "$@"
}

kopia_timer_enable() {
  _kopia_timer_cli_call enable-timer
}

kopia_timer_disable() {
  _kopia_timer_cli_call disable-timer
}

kopia_timer_remove() {
  _kopia_timer_cli_call remove-timer
}

kopia_timer_run_now() {
  _kopia_timer_cli_call run
}

kopia_timer_status_extra() {
  local last

  last="$(_kopia_timer_cli_call status 2>/dev/null | awk -F'：' '/^上次執行：/{print $2; exit}' || true)"
  [ -n "${last:-}" ] && echo "上次執行：$last"
}

tgdb_timer_define_kopia_backup_task() {
  # shellcheck disable=SC2034 # 供共用選單/回呼跨檔案讀取
  {
    TGDB_TIMER_TASK_ID="kopia_backup"
    TGDB_TIMER_TASK_TITLE="Kopia 統一備份"
    TGDB_TIMER_TIMER_UNIT="tgdb-kopia-backup.timer"
    TGDB_TIMER_SERVICE_UNIT="tgdb-kopia-backup.service"
    TGDB_TIMER_SCHEDULE_MODE="oncalendar"
    TGDB_TIMER_SCHEDULE_KEY="OnCalendar"
    TGDB_TIMER_SCHEDULE_HINT="此任務會先做 DB dump，再建立 Kopia snapshot。"
    TGDB_TIMER_ENABLE_CB="kopia_timer_enable"
    TGDB_TIMER_DISABLE_CB="kopia_timer_disable"
    TGDB_TIMER_REMOVE_CB="kopia_timer_remove"
    TGDB_TIMER_GET_SCHEDULE_CB="kopia_timer_get_schedule"
    TGDB_TIMER_SET_SCHEDULE_CB="kopia_timer_set_schedule"
    TGDB_TIMER_RUN_NOW_CB="kopia_timer_run_now"
    TGDB_TIMER_STATUS_EXTRA_CB="kopia_timer_status_extra"
    TGDB_TIMER_HEALTHCHECKS_SUPPORTED="1"
    TGDB_TIMER_RUN_VIA_RUNNER="1"
    TGDB_TIMER_CONTEXT_KIND="built_in"
    TGDB_TIMER_CONTEXT_ID="kopia_backup"
  }
}

_kopia_timer_menu() {
  tgdb_timer_task_menu "kopia_backup"
}
