#!/bin/bash

# TGDB 定時任務共用選單
# 注意：此檔案為 library，會被共用模組 source，請勿在此更改 shell options。

if [ -n "${_TGDB_TIMER_MENU_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_TIMER_MENU_LOADED=1

tgdb_timer_task_schedule_get() {
  if [ -n "${TGDB_TIMER_GET_SCHEDULE_CB:-}" ]; then
    tgdb_timer_call_callback "$TGDB_TIMER_GET_SCHEDULE_CB"
    return $?
  fi

  tgdb_timer_schedule_get "$TGDB_TIMER_TIMER_UNIT" "${TGDB_TIMER_SCHEDULE_KEY:-OnCalendar}"
}

tgdb_timer_task_schedule_set() {
  local schedule="$*"

  if [ -n "${TGDB_TIMER_SET_SCHEDULE_CB:-}" ]; then
    tgdb_timer_call_callback "$TGDB_TIMER_SET_SCHEDULE_CB" "$schedule"
    return $?
  fi

  tgdb_timer_schedule_set "$TGDB_TIMER_TIMER_UNIT" "${TGDB_TIMER_SCHEDULE_KEY:-OnCalendar}" "$schedule"
}

tgdb_timer_task_enable() {
  if [ -n "${TGDB_TIMER_ENABLE_CB:-}" ]; then
    tgdb_timer_call_callback "$TGDB_TIMER_ENABLE_CB"
    return $?
  fi

  tgdb_fail "此任務未定義開啟回呼：$TGDB_TIMER_TASK_ID" 1 || return $?
}

tgdb_timer_task_disable() {
  if [ -n "${TGDB_TIMER_DISABLE_CB:-}" ]; then
    tgdb_timer_call_callback "$TGDB_TIMER_DISABLE_CB"
    return $?
  fi

  tgdb_fail "此任務未定義關閉回呼：$TGDB_TIMER_TASK_ID" 1 || return $?
}

tgdb_timer_task_remove() {
  if [ -n "${TGDB_TIMER_REMOVE_CB:-}" ]; then
    tgdb_timer_call_callback "$TGDB_TIMER_REMOVE_CB"
    return $?
  fi

  tgdb_fail "此任務未定義移除回呼：$TGDB_TIMER_TASK_ID" 1 || return $?
}

tgdb_timer_task_run_now() {
  if [ "${TGDB_TIMER_RUN_VIA_RUNNER:-0}" = "1" ]; then
    tgdb_timer_run_via_runner "$TGDB_TIMER_TASK_ID" "manual"
    return $?
  fi

  if [ -n "${TGDB_TIMER_RUN_NOW_CB:-}" ]; then
    tgdb_timer_call_callback "$TGDB_TIMER_RUN_NOW_CB"
    return $?
  fi

  tgdb_fail "此任務未定義立即執行回呼：$TGDB_TIMER_TASK_ID" 1 || return $?
}

tgdb_timer_task_print_status() {
  local schedule

  schedule="$(tgdb_timer_task_schedule_get 2>/dev/null || true)"
  [ -z "${schedule:-}" ] && schedule="(未設定)"

  echo "任務名稱：$TGDB_TIMER_TIMER_UNIT"
  echo "啟用狀態：$(tgdb_timer_enabled_state "$TGDB_TIMER_TIMER_UNIT")"
  echo "目前狀態：$(tgdb_timer_active_state "$TGDB_TIMER_TIMER_UNIT")"
  echo "執行排程：$schedule"
  echo "systemd 排程：$(tgdb_timer_list_line "$TGDB_TIMER_TIMER_UNIT")"

  if [ -n "${TGDB_TIMER_STATUS_EXTRA_CB:-}" ]; then
    tgdb_timer_call_callback "$TGDB_TIMER_STATUS_EXTRA_CB" || true
  fi

  tgdb_timer_healthchecks_print_status || true

  if [ -n "${TGDB_TIMER_SCHEDULE_HINT:-}" ]; then
    echo "提示：$TGDB_TIMER_SCHEDULE_HINT"
  fi
}

tgdb_timer_task_oncalendar_schedule_menu() {
  local choice sched time_str dow_choice dow day

  while true; do
    clear
    echo "=================================="
    echo "❖ $TGDB_TIMER_TASK_TITLE 執行時間 ❖"
    echo "=================================="
    echo "目前排程：$(tgdb_timer_task_schedule_get 2>/dev/null || echo '(未設定)')"
    echo "----------------------------------"
    echo "1. 每日（指定時間）"
    echo "2. 每週（指定星期幾 + 時間）"
    echo "3. 每月（指定日期 + 時間）"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-3]: " choice

    case "$choice" in
      1)
        read -r -e -p "輸入每天執行時間 (HH:MM，預設 03:30): " time_str
        time_str="${time_str:-03:30}"
        if [[ ! "$time_str" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
          tgdb_err "時間格式錯誤，請使用 HH:MM。"
          sleep 1
          continue
        fi
        sched="*-*-* ${time_str}:00"
        ;;
      2)
        echo "選擇星期幾："
        echo "1. 週一 (Mon)"
        echo "2. 週二 (Tue)"
        echo "3. 週三 (Wed)"
        echo "4. 週四 (Thu)"
        echo "5. 週五 (Fri)"
        echo "6. 週六 (Sat)"
        echo "7. 週日 (Sun)"
        read -r -e -p "請輸入 [1-7]（預設 1=週一）: " dow_choice
        dow_choice="${dow_choice:-1}"
        case "$dow_choice" in
          1) dow="Mon" ;;
          2) dow="Tue" ;;
          3) dow="Wed" ;;
          4) dow="Thu" ;;
          5) dow="Fri" ;;
          6) dow="Sat" ;;
          7) dow="Sun" ;;
          *) tgdb_err "無效選項。"; sleep 1; continue ;;
        esac
        read -r -e -p "輸入執行時間 (HH:MM，預設 03:30): " time_str
        time_str="${time_str:-03:30}"
        if [[ ! "$time_str" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
          tgdb_err "時間格式錯誤，請使用 HH:MM。"
          sleep 1
          continue
        fi
        sched="$dow *-*-* ${time_str}:00"
        ;;
      3)
        read -r -e -p "輸入每月日期 (1-31，預設 1): " day
        day="${day:-1}"
        if ! [[ "$day" =~ ^[1-9]$|^[12][0-9]$|^3[01]$ ]]; then
          tgdb_err "日期必須介於 1-31。"
          sleep 1
          continue
        fi
        read -r -e -p "輸入執行時間 (HH:MM，預設 03:30): " time_str
        time_str="${time_str:-03:30}"
        if [[ ! "$time_str" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
          tgdb_err "時間格式錯誤，請使用 HH:MM。"
          sleep 1
          continue
        fi
        sched="*-*-$day ${time_str}:00"
        ;;
      0)
        return 0
        ;;
      *)
        echo "無效選項。"
        sleep 1
        continue
        ;;
    esac

    tgdb_timer_task_schedule_set "$sched" || true
    echo "✅ 已更新排程：$sched"
    ui_pause
  done
}

tgdb_timer_task_interval_schedule_menu() {
  local choice sched

  while true; do
    clear
    echo "=================================="
    echo "❖ $TGDB_TIMER_TASK_TITLE 執行時間 ❖"
    echo "=================================="
    echo "目前排程：$(tgdb_timer_task_schedule_get 2>/dev/null || echo '(未設定)')"
    echo "----------------------------------"
    echo "1. 每 7 天執行一次"
    echo "2. 每 14 天執行一次"
    echo "3. 每 30 天執行一次"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-3]: " choice

    case "$choice" in
      1) sched="7d" ;;
      2) sched="14d" ;;
      3) sched="30d" ;;
      0) return 0 ;;
      *) echo "無效選項。"; sleep 1; continue ;;
    esac

    tgdb_timer_task_schedule_set "$sched" || true
    echo "✅ 已更新排程：$sched"
    ui_pause
  done
}

tgdb_timer_task_custom_schedule_menu() {
  local prompt sched

  if [ "${TGDB_TIMER_SCHEDULE_MODE:-oncalendar}" = "interval" ]; then
    prompt="輸入 ${TGDB_TIMER_SCHEDULE_KEY:-OnUnitActiveSec}（例如 12h、7d、30d；輸入 0 取消）: "
  else
    prompt="輸入 OnCalendar（例如 daily、Mon *-*-* 04:00:00、*-*-* 03:30:00；輸入 0 取消）: "
  fi

  read -r -e -p "$prompt" sched
  if [ "${sched:-}" = "0" ] || [ -z "${sched:-}" ]; then
    echo "操作已取消。"
    ui_pause
    return 0
  fi

  tgdb_timer_task_schedule_set "$sched" || true
  ui_pause
  return 0
}

tgdb_timer_task_schedule_menu() {
  case "${TGDB_TIMER_SCHEDULE_MODE:-oncalendar}" in
    interval)
      tgdb_timer_task_interval_schedule_menu
      ;;
    *)
      tgdb_timer_task_oncalendar_schedule_menu
      ;;
  esac
}

tgdb_timer_task_menu() {
  local task_id="$1"
  local max_choice="6"
  local healthchecks_choice=""
  local special_choice=""

  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi

  tgdb_timer_registry_load_task "$task_id" || {
    ui_pause
    return 1
  }

  while true; do
    clear
    echo "=================================="
    echo "❖ $TGDB_TIMER_TASK_TITLE ❖"
    echo "=================================="
    tgdb_timer_task_print_status
    echo "----------------------------------"
    echo "1. 開啟任務"
    echo "2. 關閉任務"
    echo "3. 移除任務"
    echo "4. 調整執行時間"
    echo "5. 自訂執行時間"
    echo "6. 立即執行一次"

    max_choice="6"
    if tgdb_timer_healthchecks_supported_current; then
      healthchecks_choice=$((max_choice + 1))
      echo "$healthchecks_choice. Healthchecks 設定"
      max_choice="$healthchecks_choice"
    else
      healthchecks_choice=""
    fi

    if [ -n "${TGDB_TIMER_SPECIAL_LABEL:-}" ] && [ -n "${TGDB_TIMER_SPECIAL_CB:-}" ]; then
      special_choice=$((max_choice + 1))
      echo "$special_choice. $TGDB_TIMER_SPECIAL_LABEL"
      max_choice="$special_choice"
    else
      special_choice=""
    fi
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="

    local choice
    read -r -e -p "請輸入選擇 [0-$max_choice]: " choice
    case "$choice" in
      1) tgdb_timer_task_enable || true; ui_pause ;;
      2) tgdb_timer_task_disable || true; ui_pause ;;
      3)
        if ui_confirm_yn "確定要移除任務嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
          tgdb_timer_task_remove || true
        else
          echo "已取消"
        fi
        ui_pause
        if [ "${TGDB_TIMER_CONTEXT_KIND:-}" = "custom" ]; then
          return 0
        fi
        ;;
      4) tgdb_timer_task_schedule_menu ;;
      5) tgdb_timer_task_custom_schedule_menu ;;
      6) tgdb_timer_task_run_now || true; ui_pause ;;
      0) return 0 ;;
      *)
        if [ -n "${healthchecks_choice:-}" ] && [ "$choice" = "$healthchecks_choice" ]; then
          tgdb_timer_healthchecks_menu || true
        elif [ -n "${special_choice:-}" ] && [ "$choice" = "$special_choice" ]; then
          tgdb_timer_call_callback "$TGDB_TIMER_SPECIAL_CB" || true
        else
          echo "無效選項。"
          sleep 1
        fi
        ;;
    esac
  done
}

tgdb_timer_menu() {
  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ 定時任務管理 ❖"
    echo "=================================="

    local rows=() row id title idx=1
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      rows+=("$row")
      IFS='|' read -r id title _ _ <<<"$row"
      tgdb_timer_registry_load_task "$id" >/dev/null 2>&1 || true
      echo "$idx. $title（$(tgdb_timer_enabled_state "$TGDB_TIMER_TIMER_UNIT" 2>/dev/null || echo unknown)）"
      idx=$((idx + 1))
    done < <(tgdb_timer_registry_iter_rows)

    echo "$idx. 自訂定時任務"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="

    local choice custom_choice
    read -r -e -p "請輸入選擇 [0-$idx]: " choice
    case "$choice" in
      0)
        return 0
        ;;
      *)
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
          if [ "$choice" -eq "$idx" ] 2>/dev/null; then
            tgdb_timer_custom_menu || true
            continue
          fi
          custom_choice=$((choice - 1))
          if [ "$custom_choice" -ge 0 ] 2>/dev/null && [ "$custom_choice" -lt "${#rows[@]}" ] 2>/dev/null; then
            IFS='|' read -r id _ _ _ <<<"${rows[$custom_choice]}"
            tgdb_timer_task_menu "$id" || true
          else
            echo "無效選項。"
            sleep 1
          fi
        else
          echo "無效選項。"
          sleep 1
        fi
        ;;
    esac
  done
}
