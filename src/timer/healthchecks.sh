#!/bin/bash

# TGDB 定時任務：Healthchecks 通知支援
# 注意：此檔案為 library，會被共用模組 source，請勿在此更改 shell options。

if [ -n "${_TGDB_TIMER_HEALTHCHECKS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_TIMER_HEALTHCHECKS_LOADED=1

tgdb_timer_healthchecks_root_dir() {
  printf '%s\n' "$(rm_persist_config_dir)/timer/healthchecks"
}

tgdb_timer_healthchecks_task_dir() {
  printf '%s\n' "$(tgdb_timer_healthchecks_root_dir)/tasks"
}

tgdb_timer_healthchecks_conf_path() {
  local task_key="$1"
  printf '%s\n' "$(tgdb_timer_healthchecks_task_dir)/${task_key}.conf"
}

tgdb_timer_healthchecks_ensure_dirs() {
  mkdir -p "$(tgdb_timer_healthchecks_task_dir)" 2>/dev/null || true
}

tgdb_timer_healthchecks_task_key_for_task_id() {
  local task_id="$1"

  case "$task_id" in
    custom:*)
      printf '%s\n' "custom-${task_id#custom:}"
      ;;
    *)
      printf '%s\n' "$task_id"
      ;;
  esac
}

tgdb_timer_healthchecks_current_task_key() {
  tgdb_timer_healthchecks_task_key_for_task_id "${TGDB_TIMER_TASK_ID:-}"
}

tgdb_timer_healthchecks_supported_current() {
  [ "${TGDB_TIMER_HEALTHCHECKS_SUPPORTED:-0}" = "1" ]
}

tgdb_timer_healthchecks_conf_get() {
  local task_key="$1"
  local key="$2"
  local default_value="${3:-}"
  local conf

  conf="$(tgdb_timer_healthchecks_conf_path "$task_key")"
  if [ ! -f "$conf" ]; then
    printf '%s\n' "$default_value"
    return 0
  fi

  awk -F= -v want="$key" -v fallback="$default_value" '
    $1 == want {
      print substr($0, index($0, "=") + 1)
      found=1
      exit
    }
    END {
      if (!found) {
        print fallback
      }
    }
  ' "$conf" 2>/dev/null
}

tgdb_timer_healthchecks_enabled() {
  local task_key="$1"
  [ "$(tgdb_timer_healthchecks_conf_get "$task_key" "enabled" "0")" = "1" ]
}

tgdb_timer_healthchecks_ping_url_get() {
  local task_key="$1"
  tgdb_timer_healthchecks_conf_get "$task_key" "ping_url" ""
}

tgdb_timer_healthchecks_notify_manual_get() {
  local task_key="$1"
  tgdb_timer_healthchecks_conf_get "$task_key" "notify_manual" "1"
}

tgdb_timer_healthchecks_write_conf() {
  local task_key="$1"
  local enabled="$2"
  local ping_url="$3"
  local notify_manual="$4"
  local conf

  conf="$(tgdb_timer_healthchecks_conf_path "$task_key")"
  tgdb_timer_healthchecks_ensure_dirs
  printf 'enabled=%s\nping_url=%s\nnotify_manual=%s\n' \
    "$enabled" "$ping_url" "$notify_manual" >"$conf"
}

tgdb_timer_healthchecks_remove_conf() {
  local task_key="$1"
  rm -f -- "$(tgdb_timer_healthchecks_conf_path "$task_key")" 2>/dev/null || true
}

tgdb_timer_healthchecks_mask_url() {
  local url="$1"

  if [ -z "${url:-}" ]; then
    printf '%s\n' "(未設定)"
    return 0
  fi

  if [ "${#url}" -le 28 ]; then
    printf '%s\n' "$url"
    return 0
  fi

  printf '%s...%s\n' "${url:0:20}" "${url: -8}"
}

tgdb_timer_healthchecks_status_label() {
  local task_key="$1"
  local ping_url enabled notify_manual

  ping_url="$(tgdb_timer_healthchecks_ping_url_get "$task_key")"
  if [ -z "${ping_url:-}" ]; then
    printf '%s\n' "未設定"
    return 0
  fi

  enabled="$(tgdb_timer_healthchecks_conf_get "$task_key" "enabled" "1")"
  notify_manual="$(tgdb_timer_healthchecks_notify_manual_get "$task_key")"

  if [ "$enabled" != "1" ]; then
    printf '%s\n' "已停用"
    return 0
  fi

  if [ "$notify_manual" = "1" ]; then
    printf '%s\n' "已啟用（手動執行也通知）"
    return 0
  fi

  printf '%s\n' "已啟用（僅定時執行通知）"
}

tgdb_timer_healthchecks_print_status() {
  local task_key ping_url

  if ! tgdb_timer_healthchecks_supported_current; then
    return 0
  fi

  task_key="$(tgdb_timer_healthchecks_current_task_key)"
  ping_url="$(tgdb_timer_healthchecks_ping_url_get "$task_key")"

  echo "Healthchecks：$(tgdb_timer_healthchecks_status_label "$task_key")"
  if [ -n "${ping_url:-}" ]; then
    echo "Ping URL：$(tgdb_timer_healthchecks_mask_url "$ping_url")"
  fi
}

tgdb_timer_healthchecks_should_notify() {
  local task_id="$1"
  local origin="${2:-timer}"
  local task_key ping_url

  task_key="$(tgdb_timer_healthchecks_task_key_for_task_id "$task_id")"
  ping_url="$(tgdb_timer_healthchecks_ping_url_get "$task_key")"

  [ -n "${ping_url:-}" ] || return 1
  tgdb_timer_healthchecks_enabled "$task_key" || return 1

  if [ "$origin" = "manual" ] && [ "$(tgdb_timer_healthchecks_notify_manual_get "$task_key")" != "1" ]; then
    return 1
  fi

  return 0
}

tgdb_timer_healthchecks_send() {
  local task_id="$1"
  local event="${2:-success}"
  local result_code="${3:-0}"
  local task_key ping_url target_url curl_rc=0

  task_key="$(tgdb_timer_healthchecks_task_key_for_task_id "$task_id")"
  ping_url="$(tgdb_timer_healthchecks_ping_url_get "$task_key")"
  [ -n "${ping_url:-}" ] || return 0

  if ! command -v curl >/dev/null 2>&1; then
    tgdb_warn "未安裝 curl，略過 Healthchecks 通知：$task_id"
    return 0
  fi

  ping_url="${ping_url%/}"
  case "$event" in
    start)
      target_url="${ping_url}/start"
      curl -fsS -m 10 -o /dev/null "$target_url" >/dev/null 2>&1 || curl_rc=$?
      ;;
    fail)
      target_url="${ping_url}/fail"
      curl -fsS -m 10 -o /dev/null --data-raw "task=${task_id} rc=${result_code}" "$target_url" >/dev/null 2>&1 || curl_rc=$?
      ;;
    *)
      target_url="$ping_url"
      curl -fsS -m 10 -o /dev/null "$target_url" >/dev/null 2>&1 || curl_rc=$?
      ;;
  esac

  if [ "$curl_rc" -ne 0 ]; then
    tgdb_warn "Healthchecks ${event} 通知失敗：$task_id"
  fi

  return 0
}

tgdb_timer_healthchecks_validate_url() {
  local ping_url="$1"
  [[ "$ping_url" =~ ^https?://[^[:space:]]+$ ]]
}

tgdb_timer_healthchecks_menu() {
  local task_key enabled ping_url notify_manual choice

  if ! tgdb_timer_healthchecks_supported_current; then
    tgdb_fail "此任務目前尚未支援 Healthchecks。" 1 || return $?
  fi

  task_key="$(tgdb_timer_healthchecks_current_task_key)"

  while true; do
    enabled="$(tgdb_timer_healthchecks_conf_get "$task_key" "enabled" "0")"
    ping_url="$(tgdb_timer_healthchecks_ping_url_get "$task_key")"
    notify_manual="$(tgdb_timer_healthchecks_notify_manual_get "$task_key")"

    clear
    echo "=================================="
    echo "❖ $TGDB_TIMER_TASK_TITLE Healthchecks ❖"
    echo "=================================="
    echo "狀態：$(tgdb_timer_healthchecks_status_label "$task_key")"
    echo "Ping URL：$(tgdb_timer_healthchecks_mask_url "$ping_url")"
    echo "手動執行也通知：$([ "$notify_manual" = "1" ] && echo "是" || echo "否")"
    echo "----------------------------------"
    echo "1. 設定/更新 Ping URL"
    echo "2. 啟用/停用通知"
    echo "3. 切換手動執行也通知"
    echo "4. 測試送出成功通知"
    echo "5. 移除通知設定"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="

    read -r -e -p "請輸入選擇 [0-5]: " choice
    case "$choice" in
      1)
        read -r -e -p "輸入 Healthchecks Ping URL（輸入 0 取消）: " ping_url
        if [ "${ping_url:-}" = "0" ] || [ -z "${ping_url:-}" ]; then
          echo "操作已取消。"
          ui_pause
          continue
        fi
        if ! tgdb_timer_healthchecks_validate_url "$ping_url"; then
          tgdb_err "Ping URL 格式不合法，請使用 http:// 或 https://。"
          ui_pause
          continue
        fi
        tgdb_timer_healthchecks_write_conf "$task_key" "1" "$ping_url" "$notify_manual"
        echo "✅ 已更新 Healthchecks Ping URL。"
        ui_pause
        ;;
      2)
        if [ -z "${ping_url:-}" ]; then
          tgdb_warn "請先設定 Ping URL。"
        else
          if [ "$enabled" = "1" ]; then
            tgdb_timer_healthchecks_write_conf "$task_key" "0" "$ping_url" "$notify_manual"
            echo "✅ 已停用 Healthchecks 通知。"
          else
            tgdb_timer_healthchecks_write_conf "$task_key" "1" "$ping_url" "$notify_manual"
            echo "✅ 已啟用 Healthchecks 通知。"
          fi
        fi
        ui_pause
        ;;
      3)
        if [ "$notify_manual" = "1" ]; then
          notify_manual="0"
        else
          notify_manual="1"
        fi
        tgdb_timer_healthchecks_write_conf "$task_key" "$enabled" "$ping_url" "$notify_manual"
        echo "✅ 已更新手動執行通知設定。"
        ui_pause
        ;;
      4)
        if [ -z "${ping_url:-}" ]; then
          tgdb_warn "請先設定 Ping URL。"
        else
          tgdb_timer_healthchecks_send "${TGDB_TIMER_TASK_ID:-}" "success" "0"
          echo "✅ 已嘗試送出 Healthchecks 成功通知。"
        fi
        ui_pause
        ;;
      5)
        if ui_confirm_yn "確定要移除這個任務的 Healthchecks 設定嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
          tgdb_timer_healthchecks_remove_conf "$task_key"
          echo "✅ 已移除 Healthchecks 設定。"
        else
          echo "已取消"
        fi
        ui_pause
        ;;
      0)
        return 0
        ;;
      *)
        echo "無效選項。"
        sleep 1
        ;;
    esac
  done
}
