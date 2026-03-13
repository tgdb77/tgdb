#!/bin/bash

# TGDB 定時任務共用底層
# 注意：此檔案為 library，會被共用模組 source，請勿在此更改 shell options。

if [ -n "${_TGDB_TIMER_COMMON_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_TIMER_COMMON_LOADED=1

tgdb_timer_user_systemd_dir() {
  if declare -F rm_user_systemd_dir >/dev/null 2>&1; then
    rm_user_systemd_dir
    return 0
  fi

  printf '%s\n' "$HOME/.config/systemd/user"
}

tgdb_timer_unit_path() {
  local unit="$1"
  printf '%s\n' "$(tgdb_timer_user_systemd_dir)/$unit"
}

tgdb_timer_systemctl_user_try() {
  if declare -F _systemctl_user_try >/dev/null 2>&1; then
    _systemctl_user_try "$@"
    return $?
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    return 127
  fi

  systemctl --user "$@"
}

tgdb_timer_require_systemd_user() {
  if ! command -v systemctl >/dev/null 2>&1; then
    tgdb_fail "找不到 systemctl，無法管理定時任務（需要 systemd --user）。" 1 || return $?
  fi

  mkdir -p "$(tgdb_timer_user_systemd_dir)" 2>/dev/null || true
  return 0
}

tgdb_timer_write_user_unit() {
  local unit="$1"
  local content="$2"

  mkdir -p "$(tgdb_timer_user_systemd_dir)" 2>/dev/null || true
  printf '%b' "$content" >"$(tgdb_timer_unit_path "$unit")"
}

tgdb_timer_unit_exists() {
  local unit="$1"
  [ -f "$(tgdb_timer_unit_path "$unit")" ]
}

tgdb_timer_enabled_state() {
  local timer_unit="$1"
  local state

  state="$(tgdb_timer_systemctl_user_try is-enabled -- "$timer_unit" 2>/dev/null || true)"
  if [ -n "${state:-}" ]; then
    printf '%s\n' "$state"
    return 0
  fi

  if tgdb_timer_unit_exists "$timer_unit"; then
    printf '%s\n' "disabled"
    return 0
  fi

  printf '%s\n' "absent"
}

tgdb_timer_active_state() {
  local timer_unit="$1"
  local state

  state="$(tgdb_timer_systemctl_user_try is-active -- "$timer_unit" 2>/dev/null || true)"
  if [ -n "${state:-}" ]; then
    printf '%s\n' "$state"
    return 0
  fi

  if tgdb_timer_unit_exists "$timer_unit"; then
    printf '%s\n' "inactive"
    return 0
  fi

  printf '%s\n' "not-installed"
}

tgdb_timer_list_line() {
  local timer_unit="$1"

  tgdb_timer_systemctl_user_try list-timers --all 2>/dev/null | awk -v unit="$timer_unit" '
    $0 ~ unit {
      print
      found=1
    }
    END {
      if (!found) {
        print "(尚未出現在 systemd timers 清單)"
      }
    }
  '
}

tgdb_timer_unit_value_get_by_path() {
  local path="$1"
  local key="$2"

  [ -f "$path" ] || return 1
  awk -F= -v want="$key" '$1==want {print $2; exit}' "$path" 2>/dev/null
}

tgdb_timer_unit_value_set_by_path() {
  local path="$1"
  local key="$2"
  local value="$3"

  [ -f "$path" ] || {
    tgdb_fail "找不到 timer 檔案：$path" 1 || return $?
  }

  if grep -q "^${key}=" "$path" 2>/dev/null; then
    sed -i "s|^${key}=.*$|${key}=${value}|" "$path"
  else
    printf '\n%s=%s\n' "$key" "$value" >>"$path"
  fi

  tgdb_timer_systemctl_user_try daemon-reload >/dev/null 2>&1 || true
  return 0
}

tgdb_timer_schedule_get() {
  local timer_unit="$1"
  local key="${2:-OnCalendar}"

  tgdb_timer_unit_value_get_by_path "$(tgdb_timer_unit_path "$timer_unit")" "$key"
}

tgdb_timer_schedule_set() {
  local timer_unit="$1"
  local key="$2"
  local value="$3"
  local path

  path="$(tgdb_timer_unit_path "$timer_unit")"
  tgdb_timer_unit_value_set_by_path "$path" "$key" "$value" || return 1
  tgdb_timer_systemctl_user_try restart -- "$timer_unit" >/dev/null 2>&1 || true
  return 0
}

tgdb_timer_validate_named_frequency() {
  local freq="${1:-}"

  case "$freq" in
    daily|weekly|monthly)
      return 0
      ;;
    *)
      tgdb_fail "不支援的頻率：$freq（僅支援 daily/weekly/monthly）" 2 || return $?
      ;;
  esac
}

tgdb_timer_setup_managed() {
  local timer_unit="$1"
  local write_cb="${2:-}"
  shift 2 || true

  tgdb_timer_require_systemd_user || return 1

  if [ -z "${write_cb:-}" ]; then
    tgdb_fail "缺少 managed timer 寫入回呼：$timer_unit" 1 || return $?
  fi

  tgdb_timer_call_callback "$write_cb" "$@" || return $?
  tgdb_timer_systemctl_user_try daemon-reload >/dev/null 2>&1 || true
  tgdb_timer_systemctl_user_try enable --now -- "$timer_unit" >/dev/null 2>&1
}

tgdb_timer_enable_managed() {
  local timer_unit="$1"
  local service_unit="$2"
  local ensure_cb="${3:-}"

  tgdb_timer_require_systemd_user || return 1

  if ! tgdb_timer_unit_exists "$timer_unit" || { [ -n "${service_unit:-}" ] && ! tgdb_timer_unit_exists "$service_unit"; }; then
    if [ -n "${ensure_cb:-}" ]; then
      "$ensure_cb" || return $?
    else
      tgdb_fail "找不到 $timer_unit，且未提供建立單元的回呼。" 1 || return $?
    fi
  fi

  tgdb_timer_systemctl_user_try daemon-reload >/dev/null 2>&1 || true
  tgdb_timer_systemctl_user_try enable --now -- "$timer_unit" >/dev/null 2>&1
}

tgdb_timer_disable_units() {
  local timer_unit="$1"
  shift || true

  if ! command -v systemctl >/dev/null 2>&1; then
    tgdb_fail "找不到 systemctl，無法關閉定時任務。" 1 || return $?
  fi

  tgdb_timer_systemctl_user_try disable --now -- "$timer_unit" "$@" >/dev/null 2>&1 || true
  return 0
}

tgdb_timer_remove_units() {
  if [ "$#" -le 0 ]; then
    return 0
  fi

  local units=("$@")
  local unit

  if command -v systemctl >/dev/null 2>&1; then
    tgdb_timer_systemctl_user_try disable --now -- "${units[@]}" >/dev/null 2>&1 || true
  fi

  for unit in "${units[@]}"; do
    rm -f -- "$(tgdb_timer_unit_path "$unit")" 2>/dev/null || true
  done

  if command -v systemctl >/dev/null 2>&1; then
    tgdb_timer_systemctl_user_try daemon-reload >/dev/null 2>&1 || true
  fi

  return 0
}

tgdb_timer_call_callback() {
  local callback="${1:-}"
  shift || true

  [ -n "${callback:-}" ] || return 1
  if ! declare -F "$callback" >/dev/null 2>&1; then
    tgdb_fail "找不到定時任務回呼函式：$callback" 1 || return $?
  fi

  "$callback" "$@"
}

tgdb_timer_print_status() {
  local timer_unit="$1"
  local schedule_key="${2:-OnCalendar}"
  local extra_cb="${3:-}"
  local schedule

  schedule="$(tgdb_timer_schedule_get "$timer_unit" "$schedule_key" 2>/dev/null || true)"
  [ -z "${schedule:-}" ] && schedule="(未設定)"

  echo "任務名稱：$timer_unit"
  echo "啟用狀態：$(tgdb_timer_enabled_state "$timer_unit")"
  echo "目前狀態：$(tgdb_timer_active_state "$timer_unit")"
  echo "執行排程：$schedule"
  echo "systemd 排程：$(tgdb_timer_list_line "$timer_unit")"

  if [ -n "${extra_cb:-}" ]; then
    tgdb_timer_call_callback "$extra_cb" || true
  fi
}
