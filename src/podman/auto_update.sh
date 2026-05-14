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

_podman_auto_update_ensure_units() {
    local scope="$1"
    local dir podman_bin service_path timer_path service_content timer_content

    scope="$(_podman_scope_normalize "${scope:-user}")"
    dir="$(_podman_auto_update_systemd_dir "$scope")"
    podman_bin="$(command -v podman 2>/dev/null || printf '%s\n' "/usr/bin/podman")"
    service_path="$dir/podman-auto-update.service"
    timer_path="$dir/podman-auto-update.timer"

    service_content="[Unit]\nDescription=Podman auto-update\nDocumentation=man:podman-auto-update(1)\n\n[Service]\nType=oneshot\nExecStart=${podman_bin} auto-update\n"
    timer_content="[Unit]\nDescription=Podman auto-update timer\nDocumentation=man:podman-auto-update(1)\n\n[Timer]\nOnCalendar=daily\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"

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
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    if ! command -v systemctl >/dev/null 2>&1; then
        tgdb_fail "找不到 systemctl，無法啟用 podman-auto-update.timer" 1 || return $?
    fi
    if ! command -v podman >/dev/null 2>&1; then
        tgdb_fail "找不到 podman，無法建立 podman-auto-update.service" 1 || return $?
    fi

    _podman_auto_update_ensure_units "$scope" || {
        tgdb_warn "無法建立 podman-auto-update.service / podman-auto-update.timer"
        return 1
    }

    if [ "$scope" = "user" ]; then
        _enable_user_systemd_and_linger || true
        if _podman_systemctl user enable --now -- podman-auto-update.timer; then
            echo "✅ 已啟用：podman-auto-update.timer（rootless）"
            return 0
        fi
        tgdb_warn "無法啟用 podman-auto-update.timer（rootless；可能未安裝或系統不支援 user systemd）"
        return 1
    fi

    if _podman_systemctl system enable --now -- podman-auto-update.timer; then
        echo "✅ 已啟用：podman-auto-update.timer（rootful）"
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
