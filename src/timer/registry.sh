#!/bin/bash

# TGDB 定時任務註冊表
# 注意：此檔案為 library，會被共用模組 source，請勿在此更改 shell options。

if [ -n "${_TGDB_TIMER_REGISTRY_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_TIMER_REGISTRY_LOADED=1

TGDB_TIMER_REGISTRY=(
  "backup|自動備份|backup|tgdb_timer_define_backup_task"
  "dbbackup_all|數據庫批次匯出|dbadmin-p|tgdb_timer_define_dbbackup_all_task"
  "kopia_backup|Kopia 統一備份|kopia-p|tgdb_timer_define_kopia_backup_task"
  "nginx_ssl|Nginx SSL 續簽|nginx-p|tgdb_timer_define_nginx_ssl_task"
  "nginx_cf|Cloudflare Real-IP 更新|nginx-p|tgdb_timer_define_nginx_cf_task"
  "nginx_waf|WAF CRS 規則更新|nginx-p|tgdb_timer_define_nginx_waf_task"
)

tgdb_timer_load_module() {
  local module="$1"
  local base path alt

  [ -z "${module:-}" ] && return 0

  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "$module"
    return $?
  fi

  base="${SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  path="$base/${module}.sh"
  alt="$base/advanced/${module}.sh"

  if [ -f "$path" ]; then
    # shellcheck disable=SC1090
    source "$path"
    return 0
  fi

  if [ -f "$alt" ]; then
    # shellcheck disable=SC1090
    source "$alt"
    return 0
  fi

  tgdb_fail "找不到定時任務模組：$path（或 $alt）" 1 || return $?
}

tgdb_timer_registry_find_row() {
  local task_id="$1"
  local row id

  for row in "${TGDB_TIMER_REGISTRY[@]}"; do
    IFS='|' read -r id _ _ _ <<<"$row"
    if [ "$id" = "$task_id" ]; then
      printf '%s\n' "$row"
      return 0
    fi
  done

  return 1
}

tgdb_timer_registry_iter_rows() {
  local row
  for row in "${TGDB_TIMER_REGISTRY[@]}"; do
    printf '%s\n' "$row"
  done
}

tgdb_timer_task_reset_context() {
  # shellcheck disable=SC2034 # 供共用選單/回呼跨檔案讀取
  {
    TGDB_TIMER_TASK_ID=""
    TGDB_TIMER_TASK_TITLE=""
    TGDB_TIMER_TIMER_UNIT=""
    TGDB_TIMER_SERVICE_UNIT=""
    TGDB_TIMER_SCHEDULE_MODE=""
    TGDB_TIMER_SCHEDULE_KEY=""
    TGDB_TIMER_SCHEDULE_HINT=""
    TGDB_TIMER_SPECIAL_LABEL=""
    TGDB_TIMER_ENABLE_CB=""
    TGDB_TIMER_DISABLE_CB=""
    TGDB_TIMER_REMOVE_CB=""
    TGDB_TIMER_GET_SCHEDULE_CB=""
    TGDB_TIMER_SET_SCHEDULE_CB=""
    TGDB_TIMER_RUN_NOW_CB=""
    TGDB_TIMER_STATUS_EXTRA_CB=""
    TGDB_TIMER_SPECIAL_CB=""
    TGDB_TIMER_HEALTHCHECKS_SUPPORTED=""
    TGDB_TIMER_RUN_VIA_RUNNER=""
    TGDB_TIMER_CONTEXT_KIND=""
    TGDB_TIMER_CONTEXT_ID=""
  }
  return 0
}

tgdb_timer_registry_load_task() {
  local task_id="$1"
  local row module spec_cb

  tgdb_timer_task_reset_context

  if [[ "$task_id" == custom:* ]]; then
    tgdb_timer_custom_load_task "${task_id#custom:}"
    return $?
  fi

  row="$(tgdb_timer_registry_find_row "$task_id")" || {
    tgdb_fail "找不到定時任務：$task_id" 1 || return $?
  }

  IFS='|' read -r _ _ module spec_cb <<<"$row"
  tgdb_timer_load_module "$module" || return $?

  if ! declare -F "$spec_cb" >/dev/null 2>&1; then
    tgdb_fail "找不到定時任務規格函式：$spec_cb" 1 || return $?
  fi

  "$spec_cb"
}
