#!/bin/bash

# Podman：容器自動更新（podman auto-update）
# 說明：互動菜單已集中於 src/podman/menu.sh，此檔案保留底層輔助函式。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_podman_auto_update_systemd_dir() {
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    case "$scope" in
        system)
            if declare -F rm_system_systemd_dir >/dev/null 2>&1; then
                rm_system_systemd_dir
            else
                printf '%s\n' "/etc/systemd/system"
            fi
            ;;
        *)
            if declare -F rm_user_systemd_dir >/dev/null 2>&1; then
                rm_user_systemd_dir
            else
                printf '%s\n' "${HOME}/.config/systemd/user"
            fi
            ;;
    esac
}

_podman_auto_update_write_unit_file() {
    local scope="$1" path="$2" content="$3"
    local dir
    dir="$(dirname "$path")"

    if [ "$(_podman_scope_normalize "$scope")" = "system" ]; then
        _podman_run_scope_cmd system mkdir -p "$dir" || return 1
        printf '%b' "$content" | _podman_run_scope_cmd system tee "$path" >/dev/null
        return $?
    fi

    mkdir -p "$dir" || return 1
    printf '%b' "$content" >"$path"
}

_podman_auto_update_remove_unit_file() {
    local scope="$1" path="$2"

    [ -e "$path" ] || [ -L "$path" ] || return 0
    if [ "$(_podman_scope_normalize "$scope")" = "system" ]; then
        _podman_run_scope_cmd system rm -f "$path"
        return $?
    fi
    rm -f "$path"
}

_podman_auto_update_normalize_days() {
    local days="${1:-7}"

    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ]; then
        printf '%s\n' "$days"
        return 0
    fi

    printf '%s\n' "7"
}

_podman_auto_update_normalize_time() {
    local time_str="${1:-03:00}"

    if [[ "$time_str" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        printf '%s\n' "$time_str"
        return 0
    fi

    printf '%s\n' "03:00"
}

_podman_auto_update_timer_schedule_content() {
    local days time_str oncalendar
    days="$(_podman_auto_update_normalize_days "${1:-7}")"
    time_str="$(_podman_auto_update_normalize_time "${2:-03:00}")"

    if [ "$days" -eq 1 ]; then
        oncalendar="*-*-* ${time_str}:00"
    else
        oncalendar="*-*-1/${days} ${time_str}:00"
    fi

    printf '%b' "OnCalendar=${oncalendar}\nPersistent=true\n"
}

_podman_auto_update_parse_oncalendar_days() {
    local value="${1:-}"

    case "$value" in
        daily)
            printf '%s\n' "1"
            return 0
            ;;
        "*-*-* "*)
            printf '%s\n' "1"
            return 0
            ;;
    esac

    if [[ "$value" =~ ^\*-\*-1/([0-9]+)[[:space:]] ]]; then
        _podman_auto_update_normalize_days "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

_podman_auto_update_parse_oncalendar_time() {
    local value="${1:-}"

    if [[ "$value" =~ (^|[[:space:]])([0-2][0-9]:[0-5][0-9])(:[0-5][0-9])?($|[[:space:]]) ]]; then
        _podman_auto_update_normalize_time "${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

_podman_auto_update_timer_current_days() {
    local scope="${1:-user}"
    local timer_path oncalendar value

    scope="$(_podman_scope_normalize "$scope")"
    timer_path="$(_podman_auto_update_systemd_dir "$scope")/podman-auto-update.timer"
    [ -r "$timer_path" ] || return 1

    oncalendar="$(awk -F= '$1 == "OnCalendar" { print $2; exit }' "$timer_path" 2>/dev/null || true)"
    if [ -n "$oncalendar" ]; then
        _podman_auto_update_parse_oncalendar_days "$oncalendar"
        return $?
    fi

    value="$(awk -F= '$1 == "OnUnitActiveSec" { print $2; exit }' "$timer_path" 2>/dev/null || true)"
    [ -n "$value" ] || return 1

    case "$value" in
        *d)
            value="${value%d}"
            ;;
    esac
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$value"
}

_podman_auto_update_timer_current_time() {
    local scope="${1:-user}"
    local timer_path oncalendar

    scope="$(_podman_scope_normalize "$scope")"
    timer_path="$(_podman_auto_update_systemd_dir "$scope")/podman-auto-update.timer"
    [ -r "$timer_path" ] || return 1

    oncalendar="$(awk -F= '$1 == "OnCalendar" { print $2; exit }' "$timer_path" 2>/dev/null || true)"
    [ -n "$oncalendar" ] || return 1

    _podman_auto_update_parse_oncalendar_time "$oncalendar"
}

_podman_auto_update_ensure_units() {
    local scope="$1" days="${2:-7}" time_str="${3:-03:00}"
    local dir podman_bin service_path timer_path service_content timer_content schedule_content

    scope="$(_podman_scope_normalize "${scope:-user}")"
    days="$(_podman_auto_update_normalize_days "$days")"
    time_str="$(_podman_auto_update_normalize_time "$time_str")"
    dir="$(_podman_auto_update_systemd_dir "$scope")"
    podman_bin="$(command -v podman 2>/dev/null || printf '%s\n' "/usr/bin/podman")"
    service_path="$dir/podman-auto-update.service"
    timer_path="$dir/podman-auto-update.timer"
    schedule_content="$(_podman_auto_update_timer_schedule_content "$days" "$time_str")"

    service_content="[Unit]\nDescription=Podman auto-update\nDocumentation=man:podman-auto-update(1)\n\n[Service]\nType=oneshot\nExecStart=${podman_bin} auto-update\n"
    timer_content="[Unit]\nDescription=Podman auto-update timer\nDocumentation=man:podman-auto-update(1)\n\n[Timer]\n${schedule_content}\n[Install]\nWantedBy=timers.target\n"

    _podman_auto_update_write_unit_file "$scope" "$service_path" "$service_content" || return 1
    _podman_auto_update_write_unit_file "$scope" "$timer_path" "$timer_content" || return 1
    _podman_systemctl "$scope" daemon-reload >/dev/null 2>&1 || true
}

_podman_auto_update_remove_units() {
    local scope="$1"
    local dir

    scope="$(_podman_scope_normalize "${scope:-user}")"
    dir="$(_podman_auto_update_systemd_dir "$scope")"

    _podman_auto_update_remove_unit_file "$scope" "$dir/podman-auto-update.timer" || return 1
    _podman_auto_update_remove_unit_file "$scope" "$dir/podman-auto-update.service" || return 1
    _podman_systemctl "$scope" daemon-reload >/dev/null 2>&1 || true
    _podman_systemctl "$scope" reset-failed -- podman-auto-update.timer podman-auto-update.service >/dev/null 2>&1 || true
}

_podman_auto_update_timer_enable() {
    local scope days time_str
    scope="$(_podman_scope_normalize "${1:-user}")"
    days="$(_podman_auto_update_normalize_days "${2:-7}")"
    time_str="$(_podman_auto_update_normalize_time "${3:-03:00}")"
    if ! command -v systemctl >/dev/null 2>&1; then
        tgdb_fail "找不到 systemctl，無法啟用 podman-auto-update.timer" 1 || return $?
    fi
    if ! command -v podman >/dev/null 2>&1; then
        tgdb_fail "找不到 podman，無法建立 podman-auto-update.service" 1 || return $?
    fi

    _podman_auto_update_ensure_units "$scope" "$days" "$time_str" || {
        tgdb_warn "無法建立 podman-auto-update.service / podman-auto-update.timer"
        return 1
    }

    if [ "$scope" = "user" ]; then
        _enable_user_systemd_and_linger || true
        if _podman_systemctl user enable --now -- podman-auto-update.timer; then
            echo "✅ 已啟用：podman-auto-update.timer（rootless）"
            echo "更新排程：每 ${days} 天 ${time_str}"
            return 0
        fi
        tgdb_warn "無法啟用 podman-auto-update.timer（rootless；可能未安裝或系統不支援 user systemd）"
        return 1
    fi

    if _podman_systemctl system enable --now -- podman-auto-update.timer; then
        echo "✅ 已啟用：podman-auto-update.timer（rootful）"
        echo "更新排程：每 ${days} 天 ${time_str}"
        return 0
    fi
    tgdb_warn "無法啟用 podman-auto-update.timer（rootful；可能未安裝或系統不支援 systemd system scope）"
    return 1
}

_podman_auto_update_timer_disable() {
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    if ! command -v systemctl >/dev/null 2>&1; then
        tgdb_fail "找不到 systemctl，無法停用 podman-auto-update.timer" 1 || return $?
    fi

    if [ "$scope" = "user" ]; then
        _podman_systemctl user disable --now -- podman-auto-update.timer podman-auto-update.service || true
        _podman_auto_update_remove_units user || true
        echo "✅ 已停用並移除：podman-auto-update.timer / podman-auto-update.service（rootless）"
        return 0
    fi

    _podman_systemctl system disable --now -- podman-auto-update.timer podman-auto-update.service || true
    _podman_auto_update_remove_units system || true
    echo "✅ 已停用並移除：podman-auto-update.timer / podman-auto-update.service（rootful）"
    return 0
}
