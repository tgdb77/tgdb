#!/bin/bash

# 全系統備份：systemd 定時任務與排程選單
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_BACKUP_TIMERS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_TIMERS_LOADED=1

_backup_systemd_ready() {
    if ! command -v systemctl >/dev/null 2>&1; then
        tgdb_warn "未偵測到 systemd，無法使用自動備份。"
        return 1
    fi
    mkdir -p "$USER_SD_DIR"
    return 0
}

backup_timer_ensure_units() {
    local runner_abs svc_content tim_content

    runner_abs="$(tgdb_timer_runner_script_path)"
    svc_content="[Unit]\nDescription=TGDB 全系統備份\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$runner_abs\" run backup timer\n"
    tim_content="[Unit]\nDescription=TGDB 自動備份\n\n[Timer]\nOnCalendar=daily\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"

    tgdb_timer_write_user_unit "$BACKUP_SERVICE_NAME" "$svc_content"
    tgdb_timer_write_user_unit "$BACKUP_TIMER_NAME" "$tim_content"
}

backup_enable_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    if tgdb_timer_enable_managed "$BACKUP_TIMER_NAME" "$BACKUP_SERVICE_NAME" "backup_timer_ensure_units"; then
        echo "✅ 已開啟自動備份任務。"
        return 0
    fi

    tgdb_warn "無法直接開啟 $BACKUP_TIMER_NAME，已保留現有設定檔。"
    return 1
}

backup_disable_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    if ! tgdb_timer_unit_exists "$BACKUP_TIMER_NAME" && ! tgdb_timer_unit_exists "$BACKUP_SERVICE_NAME"; then
        tgdb_warn "尚未建立自動備份任務，無需關閉。"
        return 0
    fi

    tgdb_timer_disable_units "$BACKUP_TIMER_NAME" "$BACKUP_SERVICE_NAME" || true
    echo "✅ 已關閉自動備份任務（保留設定檔）。"
}

backup_remove_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    tgdb_timer_remove_units "$BACKUP_TIMER_NAME" "$BACKUP_SERVICE_NAME" || true
    echo "✅ 已停用並移除自動備份 timer/service。"
}

backup_timer_run_once() {
    if [ -f "$SCRIPT_DIR/fail2ban_manager.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/fail2ban_manager.sh"
        backup_fail2ban_local
    fi
    if [ -f "$SCRIPT_DIR/nftables.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/nftables.sh"
        nftables_backup
    fi
    backup_create
}

backup_select_timer_ensure_units() {
    local runner_abs svc_content tim_content

    runner_abs="$(tgdb_timer_runner_script_path)"
    svc_content="[Unit]\nDescription=TGDB 指定實例備份\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$runner_abs\" run backup_select timer\n"
    tim_content="[Unit]\nDescription=TGDB 指定實例自動備份\n\n[Timer]\nOnCalendar=daily\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"

    tgdb_timer_write_user_unit "$BACKUP_SELECT_SERVICE_NAME" "$svc_content"
    tgdb_timer_write_user_unit "$BACKUP_SELECT_TIMER_NAME" "$tim_content"
}

backup_select_enable_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    local raw
    raw="$(_backup_select_targets_get)"
    if [ -z "${raw:-}" ]; then
        tgdb_fail "尚未設定指定備份實例，請先設定後再啟用。" 1 || return $?
    fi

    if tgdb_timer_enable_managed "$BACKUP_SELECT_TIMER_NAME" "$BACKUP_SELECT_SERVICE_NAME" "backup_select_timer_ensure_units"; then
        echo "✅ 已開啟指定實例自動備份任務。"
        return 0
    fi

    tgdb_warn "無法直接開啟 $BACKUP_SELECT_TIMER_NAME，已保留現有設定檔。"
    return 1
}

backup_select_disable_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    if ! tgdb_timer_unit_exists "$BACKUP_SELECT_TIMER_NAME" && ! tgdb_timer_unit_exists "$BACKUP_SELECT_SERVICE_NAME"; then
        tgdb_warn "尚未建立指定備份自動任務，無需關閉。"
        return 0
    fi

    tgdb_timer_disable_units "$BACKUP_SELECT_TIMER_NAME" "$BACKUP_SELECT_SERVICE_NAME" || true
    echo "✅ 已關閉指定實例自動備份任務（保留設定檔）。"
}

backup_select_remove_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    tgdb_timer_remove_units "$BACKUP_SELECT_TIMER_NAME" "$BACKUP_SELECT_SERVICE_NAME" || true
    echo "✅ 已停用並移除指定實例備份 timer/service。"
}

backup_select_timer_run_once() {
    local raw
    raw="$(_backup_select_targets_get)"
    if [ -z "${raw:-}" ]; then
        tgdb_fail "尚未設定指定備份實例，無法執行指定備份。" 1 || return $?
    fi

    local -a targets=()
    _backup_select_targets_to_array "$raw" targets
    [ ${#targets[@]} -gt 0 ] || {
        tgdb_fail "指定備份實例清單為空，無法執行。" 1 || return $?
    }

    backup_create_selected "${targets[@]}"
}

backup_select_timer_get_schedule() {
    tgdb_timer_schedule_get "$BACKUP_SELECT_TIMER_NAME" "OnCalendar"
}

backup_select_timer_set_schedule() {
    local sched="$*"
    [ -n "${sched:-}" ] || {
        tgdb_fail "排程不可為空。" 2 || return $?
    }

    tgdb_timer_schedule_set "$BACKUP_SELECT_TIMER_NAME" "OnCalendar" "$sched" || return 1
    echo "✅ 已更新 $BACKUP_SELECT_TIMER_NAME 排程：$sched"
}

backup_select_timer_status_extra() {
    local raw
    raw="$(_backup_select_targets_get)"
    if [ -n "${raw:-}" ]; then
        echo "指定實例：$raw"
    else
        echo "指定實例：尚未設定"
    fi
    echo "備份位置：$BACKUP_DIR"
}

backup_select_timer_special_menu() {
    if backup_select_targets_configure_interactive; then
        ui_pause
        return 0
    fi
    ui_pause
    return 1
}

tgdb_timer_define_backup_select_task() {
    # shellcheck disable=SC2034
    {
        TGDB_TIMER_TASK_ID="backup_select"
        TGDB_TIMER_TASK_TITLE="指定實例自動備份"
        TGDB_TIMER_TIMER_UNIT="$BACKUP_SELECT_TIMER_NAME"
        TGDB_TIMER_SERVICE_UNIT="$BACKUP_SELECT_SERVICE_NAME"
        TGDB_TIMER_SCHEDULE_MODE="oncalendar"
        TGDB_TIMER_SCHEDULE_KEY="OnCalendar"
        TGDB_TIMER_SCHEDULE_HINT="OnCalendar 支援 daily/weekly/monthly，或 *-*-* 03:00:00 這類完整表達式。"
        TGDB_TIMER_SPECIAL_LABEL="設定指定備份實例"
        TGDB_TIMER_ENABLE_CB="backup_select_enable_timer"
        TGDB_TIMER_DISABLE_CB="backup_select_disable_timer"
        TGDB_TIMER_REMOVE_CB="backup_select_remove_timer"
        TGDB_TIMER_GET_SCHEDULE_CB="backup_select_timer_get_schedule"
        TGDB_TIMER_SET_SCHEDULE_CB="backup_select_timer_set_schedule"
        TGDB_TIMER_RUN_NOW_CB="backup_select_timer_run_once"
        TGDB_TIMER_STATUS_EXTRA_CB="backup_select_timer_status_extra"
        TGDB_TIMER_SPECIAL_CB="backup_select_timer_special_menu"
        TGDB_TIMER_HEALTHCHECKS_SUPPORTED="1"
        TGDB_TIMER_RUN_VIA_RUNNER="1"
        TGDB_TIMER_CONTEXT_KIND="built_in"
        TGDB_TIMER_CONTEXT_ID="backup_select"
    }
}

backup_select_timer_menu() {
    tgdb_timer_task_menu "backup_select"
}

backup_rclone_sync_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    local cur
    cur="$(_backup_rclone_remote_get 2>/dev/null || true)"

    # 簡單切換模式：
    # - 未開啟：走「新增/開啟」流程
    # - 已開啟：走「關閉」流程
    if [ -n "${cur:-}" ]; then
        echo "目前狀態：已開啟（目的：${cur%:}:tgdb-backup）"
        if ui_confirm_yn "確認關閉 Rclone 遠端同步？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            _backup_rclone_remote_disable
            echo "✅ 已關閉 Rclone 遠端同步。"
        else
            echo "操作已取消。"
        fi
        ui_pause
        return 0
    fi

    if ! command -v rclone >/dev/null 2>&1; then
        tgdb_warn "未偵測到 rclone，請先至「Rclone 掛載」功能安裝/設定後再使用。"
        ui_pause
        return 1
    fi

    echo "目前狀態：未開啟"
    echo "將在每次「建立備份」完成後，自動同步到遠端根目錄的 tgdb-backup。"
    echo ""
    echo "目前可用遠端（rclone listremotes）："
    rclone listremotes 2>/dev/null || true
    echo ""
    local remote
    read -r -e -p "輸入遠端名稱（例如 gdrive 或 gdrive:；輸入 0 取消）: " remote
    if [ "${remote:-}" = "0" ] || [ -z "${remote:-}" ]; then
        echo "操作已取消。"
        ui_pause
        return 0
    fi
    if [[ ! "$remote" =~ ^[A-Za-z0-9._-]+:?$ ]]; then
        tgdb_err "遠端名稱格式不合法：$remote"
        ui_pause
        return 1
    fi
    _backup_rclone_remote_set "$remote"
    echo "✅ 已開啟 Rclone 遠端同步：${remote%:}:tgdb-backup"

    if ui_confirm_yn "是否立即同步目前備份到遠端？(Y/n，預設 N，輸入 0 取消): " "N"; then
        _backup_rclone_sync_to_remote || true
    fi
    ui_pause
    return 0
}

backup_timer_get_schedule() {
    tgdb_timer_schedule_get "$BACKUP_TIMER_NAME" "OnCalendar"
}

backup_timer_set_schedule() {
    local sched="$*"

    [ -n "${sched:-}" ] || {
        tgdb_fail "排程不可為空。" 2 || return $?
    }

    tgdb_timer_schedule_set "$BACKUP_TIMER_NAME" "OnCalendar" "$sched" || return 1
    echo "✅ 已更新 $BACKUP_TIMER_NAME 排程：$sched"
}

backup_timer_status_extra() {
    local remote

    remote="$(_backup_rclone_remote_get 2>/dev/null || true)"
    if [ -n "${remote:-}" ]; then
        echo "Rclone 遠端同步：已啟用（目的：${remote%:}:tgdb-backup）"
    else
        echo "Rclone 遠端同步：未啟用"
    fi
    echo "備份位置：$BACKUP_DIR"
}

backup_timer_special_menu() {
    backup_rclone_sync_menu
}

tgdb_timer_define_backup_task() {
    # shellcheck disable=SC2034 # 供共用選單/回呼跨檔案讀取
    {
        TGDB_TIMER_TASK_ID="backup"
        TGDB_TIMER_TASK_TITLE="自動備份"
        TGDB_TIMER_TIMER_UNIT="$BACKUP_TIMER_NAME"
        TGDB_TIMER_SERVICE_UNIT="$BACKUP_SERVICE_NAME"
        TGDB_TIMER_SCHEDULE_MODE="oncalendar"
        TGDB_TIMER_SCHEDULE_KEY="OnCalendar"
        TGDB_TIMER_SCHEDULE_HINT="OnCalendar 支援 daily/weekly/monthly，或 *-*-* 03:00:00 這類完整表達式。"
        TGDB_TIMER_SPECIAL_LABEL="切換 Rclone 遠端同步（特殊功能）"
        TGDB_TIMER_ENABLE_CB="backup_enable_timer"
        TGDB_TIMER_DISABLE_CB="backup_disable_timer"
        TGDB_TIMER_REMOVE_CB="backup_remove_timer"
        TGDB_TIMER_GET_SCHEDULE_CB="backup_timer_get_schedule"
        TGDB_TIMER_SET_SCHEDULE_CB="backup_timer_set_schedule"
        TGDB_TIMER_RUN_NOW_CB="backup_timer_run_once"
        TGDB_TIMER_STATUS_EXTRA_CB="backup_timer_status_extra"
        TGDB_TIMER_SPECIAL_CB="backup_timer_special_menu"
        TGDB_TIMER_HEALTHCHECKS_SUPPORTED="1"
        TGDB_TIMER_RUN_VIA_RUNNER="1"
        TGDB_TIMER_CONTEXT_KIND="built_in"
        TGDB_TIMER_CONTEXT_ID="backup"
    }
}

backup_timer_menu() {
    tgdb_timer_task_menu "backup"
}

# --- 互動主選單（由 tgdb.sh 呼叫） ---

