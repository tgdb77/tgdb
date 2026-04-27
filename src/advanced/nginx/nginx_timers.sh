#!/bin/bash

# Nginx：自動任務（timers）管理（SSL 續簽 / Cloudflare Real-IP / WAF 規則）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_NGINX_TIMERS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_TIMERS_LOADED=1

NGINX_TIMERS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/advanced/nginx/nginx_common.sh
source "$NGINX_TIMERS_SCRIPT_DIR/nginx_common.sh"

_nginx_timers_init_tgdb_dir() {
  if [ -n "${TGDB_DIR:-}" ]; then
    return 0
  fi

  if declare -F load_system_config >/dev/null 2>&1; then
    load_system_config || true
  fi

  if [ -z "${TGDB_DIR:-}" ]; then
    TGDB_DIR="${HOME:-/tmp}/.tgdb/app"
  fi
}

_nginx_timers_init_tgdb_dir

NGINX_WAF_VERSION_FILE="${NGINX_WAF_VERSION_FILE:-$TGDB_DIR/nginx/modsecurity/crs.version}"

_nginx_timer_timer_unit() {
  case "$1" in
    ssl) printf '%s\n' "tgdb-ssl-renew.timer" ;;
    cf) printf '%s\n' "tgdb-cf-realip-update.timer" ;;
    waf) printf '%s\n' "tgdb-nginx-waf-crs-update.timer" ;;
    *) return 1 ;;
  esac
}

_nginx_timer_service_unit() {
  case "$1" in
    ssl) printf '%s\n' "tgdb-ssl-renew.service" ;;
    cf) printf '%s\n' "tgdb-cf-realip-update.service" ;;
    waf) printf '%s\n' "tgdb-nginx-waf-crs-update.service" ;;
    *) return 1 ;;
  esac
}

_nginx_timer_write_units() {
  local kind="$1"
  local service_unit timer_unit service_content timer_content runner_abs task_id

  service_unit="$(_nginx_timer_service_unit "$kind")" || return 1
  timer_unit="$(_nginx_timer_timer_unit "$kind")" || return 1
  runner_abs="$(tgdb_timer_runner_script_path)"

  case "$kind" in
    ssl)
      task_id="nginx_ssl"
      service_content="[Unit]\nDescription=TGDB SSL Renew All (Podman)\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$runner_abs\" run $task_id timer\n"
      timer_content="[Unit]\nDescription=Daily SSL Renew All at 03:00\n\n[Timer]\nOnCalendar=*-*-* 03:00:00\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"
      ;;
    cf)
      task_id="nginx_cf"
      service_content="[Unit]\nDescription=TGDB Cloudflare Real-IP Update\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$runner_abs\" run $task_id timer\n"
      timer_content="[Unit]\nDescription=Monthly CF Real-IP Update at 03:00\n\n[Timer]\nOnCalendar=monthly\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"
      ;;
    waf)
      task_id="nginx_waf"
      service_content="[Unit]\nDescription=TGDB Nginx WAF CRS Rule Update\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$runner_abs\" run $task_id timer\n"
      timer_content="[Unit]\nDescription=Every 14 days update OWASP CRS rules\n\n[Timer]\nOnBootSec=10m\nOnUnitActiveSec=14d\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"
      ;;
    *)
      return 1
      ;;
  esac

  tgdb_timer_write_user_unit "$service_unit" "$service_content"
  tgdb_timer_write_user_unit "$timer_unit" "$timer_content"
}

_nginx_timer_enable_kind() {
  local kind="$1"
  tgdb_timer_enable_managed "$(_nginx_timer_timer_unit "$kind")" "$(_nginx_timer_service_unit "$kind")" "_nginx_timer_ensure_${kind}"
}

_nginx_timer_disable_kind() {
  local kind="$1"
  tgdb_timer_disable_units "$(_nginx_timer_timer_unit "$kind")" "$(_nginx_timer_service_unit "$kind")"
}

_nginx_timer_remove_kind() {
  local kind="$1"
  tgdb_timer_remove_units "$(_nginx_timer_timer_unit "$kind")" "$(_nginx_timer_service_unit "$kind")"
}

_nginx_timer_get_oncalendar_kind() {
  local kind="$1"
  tgdb_timer_schedule_get "$(_nginx_timer_timer_unit "$kind")" "OnCalendar"
}

_nginx_timer_set_oncalendar_kind() {
  local kind="$1"
  local sched="$2"
  tgdb_timer_schedule_set "$(_nginx_timer_timer_unit "$kind")" "OnCalendar" "$sched" || return 1
  echo "✅ 已更新 $(_nginx_timer_timer_unit "$kind") 排程：$sched"
}

_nginx_timer_get_interval_kind() {
  local kind="$1"
  tgdb_timer_schedule_get "$(_nginx_timer_timer_unit "$kind")" "OnUnitActiveSec"
}

_nginx_timer_set_interval_kind() {
  local kind="$1"
  local sched="$2"
  tgdb_timer_schedule_set "$(_nginx_timer_timer_unit "$kind")" "OnUnitActiveSec" "$sched" || return 1
  echo "✅ 已更新 $(_nginx_timer_timer_unit "$kind") 排程：$sched"
}

_nginx_timer_waf_status_extra() {
  local version="unknown"
  local bootsec

  bootsec="$(tgdb_timer_schedule_get "$(_nginx_timer_timer_unit "waf")" "OnBootSec" 2>/dev/null || true)"
  [ -n "${bootsec:-}" ] && echo "OnBootSec：$bootsec"

  if [ -f "$NGINX_WAF_VERSION_FILE" ]; then
    version="$(head -n1 "$NGINX_WAF_VERSION_FILE" 2>/dev/null || echo unknown)"
  fi
  echo "CRS 版本：$version"
}

_nginx_timer_run_now_kind() {
  case "$1" in
    ssl)
      bash "$SSL_AUTO_RENEW_P" renew-all
      ;;
    cf)
      bash "$SSL_AUTO_RENEW_P" cf-realip-update
      ;;
    waf)
      if [ -f "$NGINX_WAF_MAINT_P" ]; then
        bash "$NGINX_WAF_MAINT_P" sync-crs
      else
        tgdb_warn "找不到 WAF 維護腳本：$NGINX_WAF_MAINT_P"
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

_nginx_timer_print_brief() {
  local task_id="$1"

  tgdb_timer_registry_load_task "$task_id" >/dev/null 2>&1 || return 1
  echo "$TGDB_TIMER_TASK_TITLE：$(tgdb_timer_enabled_state "$TGDB_TIMER_TIMER_UNIT") / $(tgdb_timer_task_schedule_get 2>/dev/null || echo '(未設定)')"
}

_nginx_timer_context_kind() {
  case "${TGDB_TIMER_CONTEXT_ID:-${TGDB_TIMER_TASK_ID:-}}" in
    nginx_ssl) printf '%s\n' "ssl" ;;
    nginx_cf) printf '%s\n' "cf" ;;
    nginx_waf) printf '%s\n' "waf" ;;
    *) return 1 ;;
  esac
}

_nginx_timer_ensure_ssl() { _nginx_timer_write_units "ssl"; }
_nginx_timer_ensure_cf() { _nginx_timer_write_units "cf"; }
_nginx_timer_ensure_waf() { _nginx_timer_write_units "waf"; }

nginx_timer_enable() {
  local kind
  kind="$(_nginx_timer_context_kind)" || return 1
  _nginx_timer_enable_kind "$kind" || return 1
  echo "✅ 已開啟：$(_nginx_timer_timer_unit "$kind")"
}

nginx_timer_disable() {
  local kind
  kind="$(_nginx_timer_context_kind)" || return 1
  _nginx_timer_disable_kind "$kind"
  echo "✅ 已關閉：$(_nginx_timer_timer_unit "$kind")（保留設定檔）"
}

nginx_timer_remove() {
  local kind
  kind="$(_nginx_timer_context_kind)" || return 1
  _nginx_timer_remove_kind "$kind"
  echo "✅ 已移除：$(_nginx_timer_timer_unit "$kind") / $(_nginx_timer_service_unit "$kind")"
}

nginx_timer_get_schedule() {
  local kind
  kind="$(_nginx_timer_context_kind)" || return 1

  case "$kind" in
    waf) _nginx_timer_get_interval_kind "$kind" ;;
    *) _nginx_timer_get_oncalendar_kind "$kind" ;;
  esac
}

nginx_timer_set_schedule() {
  local kind
  kind="$(_nginx_timer_context_kind)" || return 1

  case "$kind" in
    waf) _nginx_timer_set_interval_kind "$kind" "$*" ;;
    *) _nginx_timer_set_oncalendar_kind "$kind" "$*" ;;
  esac
}

nginx_timer_run_now() {
  local kind
  kind="$(_nginx_timer_context_kind)" || return 1
  _nginx_timer_run_now_kind "$kind"
}

_nginx_timer_define_task() {
  local task_id="$1"
  local title="$2"
  local kind="$3"
  local schedule_mode="$4"
  local schedule_key="$5"
  local schedule_hint="${6:-}"
  local status_extra_cb="${7:-}"

  # shellcheck disable=SC2034 # 供共用選單/回呼跨檔案讀取
  {
    TGDB_TIMER_TASK_ID="$task_id"
    TGDB_TIMER_TASK_TITLE="$title"
    TGDB_TIMER_TIMER_UNIT="$(_nginx_timer_timer_unit "$kind")"
    TGDB_TIMER_SERVICE_UNIT="$(_nginx_timer_service_unit "$kind")"
    TGDB_TIMER_SCHEDULE_MODE="$schedule_mode"
    TGDB_TIMER_SCHEDULE_KEY="$schedule_key"
    TGDB_TIMER_SCHEDULE_HINT="$schedule_hint"
    TGDB_TIMER_ENABLE_CB="nginx_timer_enable"
    TGDB_TIMER_DISABLE_CB="nginx_timer_disable"
    TGDB_TIMER_REMOVE_CB="nginx_timer_remove"
    TGDB_TIMER_GET_SCHEDULE_CB="nginx_timer_get_schedule"
    TGDB_TIMER_SET_SCHEDULE_CB="nginx_timer_set_schedule"
    TGDB_TIMER_RUN_NOW_CB="nginx_timer_run_now"
    TGDB_TIMER_STATUS_EXTRA_CB="$status_extra_cb"
    TGDB_TIMER_HEALTHCHECKS_SUPPORTED="1"
    TGDB_TIMER_RUN_VIA_RUNNER="1"
    TGDB_TIMER_CONTEXT_KIND="built_in"
    TGDB_TIMER_CONTEXT_ID="$task_id"
  }
}

tgdb_timer_define_nginx_ssl_task() {
  _nginx_timer_define_task \
    "nginx_ssl" \
    "Nginx SSL 續簽" \
    "ssl" \
    "oncalendar" \
    "OnCalendar" \
    "SSL 續簽任務會在執行前暫停 Nginx，再自動驗證與重載。"
}

tgdb_timer_define_nginx_cf_task() {
  _nginx_timer_define_task \
    "nginx_cf" \
    "Cloudflare Real-IP 更新" \
    "cf" \
    "oncalendar" \
    "OnCalendar"
}

tgdb_timer_define_nginx_waf_task() {
  _nginx_timer_define_task \
    "nginx_waf" \
    "WAF CRS 規則更新" \
    "waf" \
    "interval" \
    "OnUnitActiveSec" \
    "此任務保留 OnBootSec=10m，畫面顯示的是週期更新間隔。" \
    "_nginx_timer_waf_status_extra"
}

nginx_p_timers_menu() {
  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ 自動任務設定（SSL/CF/WAF）❖"
    echo "=================================="
    _nginx_timer_print_brief "nginx_ssl" || true
    _nginx_timer_print_brief "nginx_cf" || true
    _nginx_timer_print_brief "nginx_waf" || true
    echo "----------------------------------"
    echo "1. 管理 SSL 續簽任務"
    echo "2. 管理 Cloudflare Real-IP 更新任務"
    echo "3. 管理 WAF CRS 規則更新任務"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-3]: " c
    case "$c" in
      1) tgdb_timer_task_menu "nginx_ssl" || true ;;
      2) tgdb_timer_task_menu "nginx_cf" || true ;;
      3) tgdb_timer_task_menu "nginx_waf" || true ;;
      0) return 0 ;;
      *) echo "無效選項"; sleep 1 ;;
    esac
  done
}
