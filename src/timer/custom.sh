#!/bin/bash

# TGDB 自訂定時任務
# 注意：此檔案為 library，會被共用模組 source，請勿在此更改 shell options。

if [ -n "${_TGDB_TIMER_CUSTOM_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_TIMER_CUSTOM_LOADED=1

tgdb_timer_custom_root_dir() {
  printf '%s\n' "$(rm_persist_config_dir)/timer/custom"
}

tgdb_timer_custom_meta_dir() {
  printf '%s\n' "$(tgdb_timer_custom_root_dir)/tasks"
}

tgdb_timer_custom_bin_dir() {
  printf '%s\n' "$(tgdb_timer_custom_root_dir)/bin"
}

tgdb_timer_custom_conf_path() {
  local task_id="$1"
  printf '%s\n' "$(tgdb_timer_custom_meta_dir)/${task_id}.conf"
}

tgdb_timer_custom_script_path() {
  local task_id="$1"
  printf '%s\n' "$(tgdb_timer_custom_bin_dir)/${task_id}.sh"
}

tgdb_timer_custom_timer_unit() {
  local task_id="$1"
  printf '%s\n' "tgdb-custom-${task_id}.timer"
}

tgdb_timer_custom_service_unit() {
  local task_id="$1"
  printf '%s\n' "tgdb-custom-${task_id}.service"
}

tgdb_timer_custom_ensure_dirs() {
  mkdir -p "$(tgdb_timer_custom_meta_dir)" "$(tgdb_timer_custom_bin_dir)" 2>/dev/null || true
}

tgdb_timer_custom_is_valid_id() {
  local task_id="$1"
  [[ "$task_id" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

tgdb_timer_custom_conf_get() {
  local task_id="$1"
  local key="$2"
  local default_value="${3:-}"
  local conf

  conf="$(tgdb_timer_custom_conf_path "$task_id")"
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

tgdb_timer_custom_conf_write() {
  local task_id="$1"
  local title="$2"
  local description="$3"
  local schedule="$4"
  local script_path="$5"
  local conf

  conf="$(tgdb_timer_custom_conf_path "$task_id")"
  tgdb_timer_custom_ensure_dirs
  cat >"$conf" <<EOF
id=$task_id
title=$title
description=$description
schedule_mode=oncalendar
schedule_value=$schedule
script_path=$script_path
persistent=true
EOF
}

tgdb_timer_custom_script_write_default() {
  local task_id="$1"
  local title="$2"
  local script

  script="$(tgdb_timer_custom_script_path "$task_id")"
  if [ -f "$script" ]; then
    chmod +x "$script" 2>/dev/null || true
    return 0
  fi

  tgdb_timer_custom_ensure_dirs
  cat >"$script" <<EOF
#!/bin/bash

# $title
# 說明：請在此填入你的自訂定時任務內容。

echo "自訂定時任務：$title"
date '+%F %T'
EOF
  chmod +x "$script" 2>/dev/null || true
}

tgdb_timer_custom_list_ids() {
  local meta_dir
  meta_dir="$(tgdb_timer_custom_meta_dir)"
  [ -d "$meta_dir" ] || return 0

  find "$meta_dir" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' 2>/dev/null \
    | sed 's/\.conf$//' \
    | LC_ALL=C sort -u
}

tgdb_timer_custom_status_extra() {
  local task_id="$TGDB_TIMER_CONTEXT_ID"
  local script_path description

  script_path="$(tgdb_timer_custom_conf_get "$task_id" "script_path" "$(tgdb_timer_custom_script_path "$task_id")")"
  description="$(tgdb_timer_custom_conf_get "$task_id" "description" "")"

  echo "腳本路徑：$script_path"
  if [ -n "${description:-}" ]; then
    echo "任務說明：$description"
  fi
}

tgdb_timer_custom_get_schedule() {
  local task_id="$TGDB_TIMER_CONTEXT_ID"
  tgdb_timer_custom_conf_get "$task_id" "schedule_value" "daily"
}

tgdb_timer_custom_set_schedule() {
  local schedule="$*"
  local task_id="$TGDB_TIMER_CONTEXT_ID"
  local title description script_path timer_unit

  [ -n "${schedule:-}" ] || {
    tgdb_fail "排程不可為空。" 2 || return $?
  }

  title="$(tgdb_timer_custom_conf_get "$task_id" "title" "$task_id")"
  description="$(tgdb_timer_custom_conf_get "$task_id" "description" "")"
  script_path="$(tgdb_timer_custom_conf_get "$task_id" "script_path" "$(tgdb_timer_custom_script_path "$task_id")")"
  timer_unit="$(tgdb_timer_custom_timer_unit "$task_id")"

  tgdb_timer_custom_conf_write "$task_id" "$title" "$description" "$schedule" "$script_path"
  if tgdb_timer_unit_exists "$timer_unit"; then
    tgdb_timer_schedule_set "$timer_unit" "OnCalendar" "$schedule" || return 1
  fi
  echo "✅ 已更新 $(tgdb_timer_custom_timer_unit "$task_id") 排程：$schedule"
}

tgdb_timer_custom_ensure_units() {
  local task_id="$TGDB_TIMER_CONTEXT_ID"
  local title schedule persistent timer_unit service_unit runner_path
  local service_content timer_content

  title="$(tgdb_timer_custom_conf_get "$task_id" "title" "$task_id")"
  schedule="$(tgdb_timer_custom_conf_get "$task_id" "schedule_value" "daily")"
  persistent="$(tgdb_timer_custom_conf_get "$task_id" "persistent" "true")"
  timer_unit="$(tgdb_timer_custom_timer_unit "$task_id")"
  service_unit="$(tgdb_timer_custom_service_unit "$task_id")"
  runner_path="$(tgdb_timer_runner_script_path)"

  tgdb_timer_custom_script_write_default "$task_id" "$title"

  service_content="[Unit]\nDescription=TGDB 自訂任務：$title\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$runner_path\" run custom:$task_id timer\n"

  timer_content="[Unit]\nDescription=TGDB 自訂任務：$title\n\n[Timer]\nOnCalendar=$schedule\nPersistent=$persistent\n\n[Install]\nWantedBy=timers.target\n"

  tgdb_timer_write_user_unit "$service_unit" "$service_content"
  tgdb_timer_write_user_unit "$timer_unit" "$timer_content"
}

tgdb_timer_custom_enable() {
  local task_id="$TGDB_TIMER_CONTEXT_ID"
  tgdb_timer_enable_managed "$(tgdb_timer_custom_timer_unit "$task_id")" "$(tgdb_timer_custom_service_unit "$task_id")" "tgdb_timer_custom_ensure_units" || return 1
  echo "✅ 已開啟自訂定時任務：$task_id"
}

tgdb_timer_custom_disable() {
  local task_id="$TGDB_TIMER_CONTEXT_ID"
  tgdb_timer_disable_units "$(tgdb_timer_custom_timer_unit "$task_id")" "$(tgdb_timer_custom_service_unit "$task_id")"
  echo "✅ 已關閉自訂定時任務：$task_id（保留設定檔）"
}

tgdb_timer_custom_remove() {
  local task_id="$TGDB_TIMER_CONTEXT_ID"

  tgdb_timer_remove_units "$(tgdb_timer_custom_timer_unit "$task_id")" "$(tgdb_timer_custom_service_unit "$task_id")"
  rm -f -- "$(tgdb_timer_custom_conf_path "$task_id")" "$(tgdb_timer_custom_script_path "$task_id")" 2>/dev/null || true
  tgdb_timer_healthchecks_remove_conf "$(tgdb_timer_healthchecks_task_key_for_task_id "custom:$task_id")"
  echo "✅ 已移除自訂定時任務：$task_id"
}

tgdb_timer_custom_run_now() {
  local task_id="$TGDB_TIMER_CONTEXT_ID"
  local script_path

  script_path="$(tgdb_timer_custom_conf_get "$task_id" "script_path" "$(tgdb_timer_custom_script_path "$task_id")")"
  if [ ! -f "$script_path" ]; then
    tgdb_fail "找不到自訂任務腳本：$script_path" 1 || return $?
  fi

  chmod +x "$script_path" 2>/dev/null || true
  /bin/bash "$script_path"
}

tgdb_timer_custom_special_menu() {
  local task_id="$TGDB_TIMER_CONTEXT_ID"
  local script_path

  if ! ensure_editor; then
    tgdb_fail "找不到可用編輯器（請安裝 nano/vim/vi 或設定 EDITOR）。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  script_path="$(tgdb_timer_custom_conf_get "$task_id" "script_path" "$(tgdb_timer_custom_script_path "$task_id")")"
  tgdb_timer_custom_script_write_default "$task_id" "$(tgdb_timer_custom_conf_get "$task_id" "title" "$task_id")"

  echo "→ 啟動編輯器：$EDITOR"
  echo "檔案：$script_path"
  "$EDITOR" "$script_path"
  return 0
}

tgdb_timer_custom_load_task() {
  local task_id="$1"
  local conf

  conf="$(tgdb_timer_custom_conf_path "$task_id")"
  [ -f "$conf" ] || {
    tgdb_fail "找不到自訂定時任務：$task_id" 1 || return $?
  }

  # shellcheck disable=SC2034 # 供共用選單/回呼跨檔案讀取
  {
    TGDB_TIMER_TASK_ID="custom:$task_id"
    TGDB_TIMER_TASK_TITLE="$(tgdb_timer_custom_conf_get "$task_id" "title" "$task_id")"
    TGDB_TIMER_TIMER_UNIT="$(tgdb_timer_custom_timer_unit "$task_id")"
    TGDB_TIMER_SERVICE_UNIT="$(tgdb_timer_custom_service_unit "$task_id")"
    TGDB_TIMER_SCHEDULE_MODE="oncalendar"
    TGDB_TIMER_SCHEDULE_KEY="OnCalendar"
    TGDB_TIMER_SPECIAL_LABEL="編輯腳本（特殊功能）"
    TGDB_TIMER_ENABLE_CB="tgdb_timer_custom_enable"
    TGDB_TIMER_DISABLE_CB="tgdb_timer_custom_disable"
    TGDB_TIMER_REMOVE_CB="tgdb_timer_custom_remove"
    TGDB_TIMER_GET_SCHEDULE_CB="tgdb_timer_custom_get_schedule"
    TGDB_TIMER_SET_SCHEDULE_CB="tgdb_timer_custom_set_schedule"
    TGDB_TIMER_RUN_NOW_CB="tgdb_timer_custom_run_now"
    TGDB_TIMER_STATUS_EXTRA_CB="tgdb_timer_custom_status_extra"
    TGDB_TIMER_SPECIAL_CB="tgdb_timer_custom_special_menu"
    TGDB_TIMER_HEALTHCHECKS_SUPPORTED="1"
    TGDB_TIMER_RUN_VIA_RUNNER="1"
    TGDB_TIMER_CONTEXT_KIND="custom"
    TGDB_TIMER_CONTEXT_ID="$task_id"
  }
}

tgdb_timer_custom_create_interactive() {
  local task_id title description schedule
  local script_path rc=0

  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi

  tgdb_timer_custom_ensure_dirs

  while true; do
    read -r -e -p "輸入任務代號（小寫英數、底線、連字號；輸入 0 取消）: " task_id
    if [ "${task_id:-}" = "0" ] || [ -z "${task_id:-}" ]; then
      echo "操作已取消。"
      return 0
    fi
    if ! tgdb_timer_custom_is_valid_id "$task_id"; then
      tgdb_err "任務代號格式不合法，請使用小寫英數、底線或連字號。"
      continue
    fi
    if [ -f "$(tgdb_timer_custom_conf_path "$task_id")" ]; then
      tgdb_err "任務代號已存在：$task_id"
      continue
    fi
    break
  done

  read -r -e -p "輸入任務名稱（預設：$task_id）: " title
  title="${title:-$task_id}"
  read -r -e -p "輸入任務說明（可留空）: " description
  read -r -e -p "輸入執行排程 OnCalendar（預設：daily）: " schedule
  schedule="${schedule:-daily}"

  script_path="$(tgdb_timer_custom_script_path "$task_id")"
  tgdb_timer_custom_conf_write "$task_id" "$title" "$description" "$schedule" "$script_path"
  tgdb_timer_custom_script_write_default "$task_id" "$title"

  echo "✅ 已建立自訂定時任務：$title"
  echo "腳本位置：$script_path"

  if ensure_editor && ui_confirm_yn "是否立即編輯任務腳本？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    "$EDITOR" "$script_path"
  else
    rc=$?
    [ "$rc" -eq 2 ] && echo "已略過編輯。"
  fi

  if ui_confirm_yn "是否立即開啟此任務？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    tgdb_timer_custom_load_task "$task_id" || return 1
    tgdb_timer_custom_enable || true
    ui_pause "按任意鍵返回..."
  fi
}

tgdb_timer_custom_menu() {
  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ 自訂定時任務 ❖"
    echo "=================================="
    echo "1. 新增自訂任務"
    echo "----------------------------------"

    local ids=() task_id idx=2
    while IFS= read -r task_id; do
      [ -n "$task_id" ] || continue
      ids+=("$task_id")
      echo "$idx. $(tgdb_timer_custom_conf_get "$task_id" "title" "$task_id")"
      idx=$((idx + 1))
    done < <(tgdb_timer_custom_list_ids)

    if [ ${#ids[@]} -eq 0 ]; then
      echo "（目前尚無自訂定時任務）"
    fi

    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="

    local choice pick_index
    read -r -e -p "請輸入選擇 [0-$((idx - 1))]: " choice
    case "$choice" in
      1)
        tgdb_timer_custom_create_interactive || true
        ;;
      0)
        return 0
        ;;
      *)
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
          pick_index=$((choice - 2))
          if [ "$pick_index" -ge 0 ] 2>/dev/null && [ "$pick_index" -lt "${#ids[@]}" ] 2>/dev/null; then
            tgdb_timer_task_menu "custom:${ids[$pick_index]}" || true
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
