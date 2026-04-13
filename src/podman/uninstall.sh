#!/bin/bash

# Podman：完全移除環境（危險）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_safe_rm_rf() {
    local p="$1"
    [ -z "$p" ] && return 1
    [ "$p" = "/" ] && return 1
    case "$p" in
        "$HOME"/*|"${XDG_RUNTIME_DIR:-/run/user/$UID}"/*)
            rm -rf -- "$p" 2>/dev/null || true
            ;;
        *)
            tgdb_warn "跳過不安全路徑：$p"
            ;;
    esac
}

_root_home_for_uninstall() {
    local root_home=""
    if command -v getent >/dev/null 2>&1; then
        root_home="$(getent passwd root 2>/dev/null | awk -F: 'NF >= 6 {print $6; exit}')"
    fi
    printf '%s\n' "${root_home:-/root}"
}

_safe_rootful_rm_rf() {
    local p="$1"
    local root_home=""
    root_home="$(_root_home_for_uninstall)"

    [ -z "$p" ] && return 1
    [ "$p" = "/" ] && return 1

    case "$p" in
        /etc/containers|/var/lib/containers|/var/cache/containers|/etc/cni|/var/lib/cni|/run/containers|/run/podman|"$root_home"/.config/containers|"$root_home"/.local/share/containers|"$root_home"/.cache/containers|"$root_home"/.config/cni|"$root_home"/.local/share/cni)
            _podman_run_scope_cmd system rm -rf -- "$p" 2>/dev/null || true
            ;;
        *)
            tgdb_warn "跳過不安全的 rootful 路徑：$p"
            ;;
    esac
}

_can_manage_system_scope_for_uninstall() {
    if _podman_is_root; then
        return 0
    fi
    command -v sudo >/dev/null 2>&1
}

_list_rootful_quadlet_records_for_uninstall() {
    if declare -F rm_list_tgdb_runtime_quadlet_files_by_mode >/dev/null 2>&1; then
        rm_list_tgdb_runtime_quadlet_files_by_mode rootful 2>/dev/null || true
        return 0
    fi

    _podman_collect_unit_records system container network volume pod device kube image 2>/dev/null \
      | awk -F'\t' 'NF>=3 {print "system\t\t" $2 "\t" $3 "\t1"}'
}

_disable_user_podman_units() {
    _systemctl_user_try disable --now -- podman-auto-update.timer podman-auto-update.service || true

    local unit
    while IFS= read -r unit; do
        [ -n "$unit" ] || continue
        _unit_try_disable_now "$unit"
    done < <(_list_user_units container network volume pod device kube image)

    _systemctl_user_try reset-failed || true
}

_disable_rootful_podman_units() {
    if ! _can_manage_system_scope_for_uninstall; then
        tgdb_warn "缺少 sudo，略過 rootful 單元停用。"
        return 0
    fi

    _podman_systemctl system disable --now -- podman-auto-update.timer podman-auto-update.service || true

    local line base
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        IFS=$'\t' read -r _scope _service base _path _managed <<< "$line"
        [ -n "${base:-}" ] || continue
        _unit_try_disable_now "system::$base" || true
    done < <(_list_rootful_quadlet_records_for_uninstall)

    _podman_systemctl system reset-failed || true
}

_purge_user_quadlet_files() {
    if declare -F rm_list_tgdb_runtime_quadlet_files_by_mode >/dev/null 2>&1; then
        local -a records=()
        local line
        while IFS= read -r line; do
            [ -n "$line" ] && records+=("$line")
        done < <(rm_list_tgdb_runtime_quadlet_files_by_mode rootless 2>/dev/null || true)

        [ ${#records[@]} -gt 0 ] || return 0

        local base path
        for line in "${records[@]}"; do
            IFS=$'\t' read -r _scope _service base path _managed <<< "$line"
            [ -n "${base:-}" ] || continue
            _unit_try_disable_now "$base" || true
        done
        for line in "${records[@]}"; do
            IFS=$'\t' read -r _scope _service base path _managed <<< "$line"
            [ -n "${path:-}" ] || continue
            rm -f -- "$path" 2>/dev/null || true
        done
        _systemctl_user_try daemon-reload || true
        return 0
    fi

    local user_units_dir
    user_units_dir="$(rm_user_units_dir)"
    [ -n "$user_units_dir" ] || return 0
    [ -d "$user_units_dir" ] || return 0

    find "$user_units_dir" -maxdepth 1 \( -type f -o -type l \) -exec rm -f -- {} + 2>/dev/null || true
    _systemctl_user_try daemon-reload || true
}

_purge_rootful_quadlet_files() {
    if ! _can_manage_system_scope_for_uninstall; then
        tgdb_warn "缺少 sudo，略過 rootful 單元檔清理。"
        return 0
    fi

    if declare -F rm_list_tgdb_runtime_quadlet_files_by_mode >/dev/null 2>&1; then
        local -a records=()
        local line
        while IFS= read -r line; do
            [ -n "$line" ] && records+=("$line")
        done < <(_list_rootful_quadlet_records_for_uninstall)

        [ ${#records[@]} -gt 0 ] || return 0

        local service path service_dir
        for line in "${records[@]}"; do
            IFS=$'\t' read -r _scope service _base path _managed <<< "$line"
            [ -n "${path:-}" ] || continue
            _podman_run_scope_cmd system rm -f -- "$path" 2>/dev/null || true
            if [ -n "${service:-}" ]; then
                service_dir="$(_podman_service_runtime_unit_dir system "$service" 2>/dev/null || true)"
                if [ -n "$service_dir" ]; then
                    _podman_run_scope_cmd system rmdir --ignore-fail-on-non-empty "$service_dir" 2>/dev/null || true
                fi
            fi
        done
        local runtime_root=""
        runtime_root="$(_podman_tgdb_runtime_unit_root system 2>/dev/null || true)"
        if [ -n "$runtime_root" ]; then
            _podman_run_scope_cmd system rmdir --ignore-fail-on-non-empty "$runtime_root" 2>/dev/null || true
        fi
        _podman_systemctl system daemon-reload || true
        return 0
    fi

    local system_units_dir
    system_units_dir="$(_podman_unit_dir system)"
    [ -n "$system_units_dir" ] || return 0
    _podman_run_scope_cmd system find "$system_units_dir" -maxdepth 1 \( -type f -o -type l \) -exec rm -f -- {} + 2>/dev/null || true
    _podman_systemctl system daemon-reload || true
}

_nuke_rootless_podman_resources() {
    if command -v podman >/dev/null 2>&1; then
        podman pod rm -a -f 2>/dev/null || true
        podman rm -a -f 2>/dev/null || true
        podman volume rm -a -f 2>/dev/null || true
        podman network prune -f 2>/dev/null || true
        podman image prune -a -f 2>/dev/null || true
        podman system prune -a -f 2>/dev/null || true
    fi
}

_nuke_rootful_podman_resources() {
    if ! _can_manage_system_scope_for_uninstall; then
        tgdb_warn "缺少 sudo，略過 rootful Podman 資源清理。"
        return 0
    fi

    if command -v podman >/dev/null 2>&1; then
        _podman_podman_cmd system pod rm -a -f 2>/dev/null || true
        _podman_podman_cmd system rm -a -f 2>/dev/null || true
        _podman_podman_cmd system volume rm -a -f 2>/dev/null || true
        _podman_podman_cmd system network prune -f 2>/dev/null || true
        _podman_podman_cmd system image prune -a -f 2>/dev/null || true
        _podman_podman_cmd system system prune -a -f 2>/dev/null || true
    fi
}

_purge_user_podman_dirs() {
    _safe_rm_rf "$HOME/.config/containers"
    _safe_rm_rf "$HOME/.local/share/containers"
    _safe_rm_rf "$HOME/.cache/containers"
    _safe_rm_rf "$HOME/.config/cni"
    _safe_rm_rf "$HOME/.local/share/cni"
    _safe_rm_rf "${XDG_RUNTIME_DIR:-/run/user/$UID}/containers"
}

_purge_rootful_podman_dirs() {
    if ! _can_manage_system_scope_for_uninstall; then
        tgdb_warn "缺少 sudo，略過 rootful Podman 目錄清理。"
        return 0
    fi

    local root_home=""
    root_home="$(_root_home_for_uninstall)"

    _safe_rootful_rm_rf "/etc/containers"
    _safe_rootful_rm_rf "/var/lib/containers"
    _safe_rootful_rm_rf "/var/cache/containers"
    _safe_rootful_rm_rf "/etc/cni"
    _safe_rootful_rm_rf "/var/lib/cni"
    _safe_rootful_rm_rf "/run/containers"
    _safe_rootful_rm_rf "/run/podman"
    _safe_rootful_rm_rf "$root_home/.config/containers"
    _safe_rootful_rm_rf "$root_home/.local/share/containers"
    _safe_rootful_rm_rf "$root_home/.cache/containers"
    _safe_rootful_rm_rf "$root_home/.config/cni"
    _safe_rootful_rm_rf "$root_home/.local/share/cni"
}

_remove_podman_packages() {
    local marker polkit_pkg
    marker="$(_podman_polkit_marker_path)"

    pkg_purge "podman" || true

    if [ -n "${marker:-}" ] && [ -f "$marker" ]; then
        polkit_pkg="$(cat "$marker" 2>/dev/null || true)"
        if [ -n "${polkit_pkg:-}" ]; then
            pkg_purge "$polkit_pkg" || true
        fi
        rm -f "$marker" 2>/dev/null || true
    fi

    pkg_autoremove || true
    sudo systemctl disable --now podman-auto-update.timer podman-auto-update.service 2>/dev/null || true
}

_run_podman_uninstall_flow() {
    echo "→ 停用使用者層級 Podman 相關服務..."
    _disable_user_podman_units

    echo "→ 刪除 rootless Quadlet 單元檔..."
    _purge_user_quadlet_files

    echo "→ 停用 rootful Podman 相關服務..."
    _disable_rootful_podman_units

    echo "→ 刪除 TGDB 管理的 rootful Quadlet 單元檔..."
    _purge_rootful_quadlet_files

    echo "→ 刪除 rootless Podman 全部資源..."
    _nuke_rootless_podman_resources

    echo "→ 刪除 rootful Podman 全部資源..."
    _nuke_rootful_podman_resources

    echo "→ 清理使用者 Podman 目錄..."
    _purge_user_podman_dirs

    echo "→ 清理 rootful Podman 目錄..."
    _purge_rootful_podman_dirs

    echo "→ 關閉使用者 linger..."
    if command -v loginctl >/dev/null 2>&1; then
        if command -v sudo >/dev/null 2>&1; then
            sudo loginctl disable-linger "$USER" >/dev/null 2>&1 || true
        else
            loginctl disable-linger "$USER" >/dev/null 2>&1 || true
        fi
    fi

    echo "→ 移除系統套件 podman（以及 TGDB 自動安裝的 polkit/policykit-1）..."
    _remove_podman_packages

    echo "→ 復原 sysctl 特權埠設定..."
    _revert_sysctl_unprivileged_ports
}

uninstall_podman_environment() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    clear
    echo "=================================="
    tgdb_warn "完全移除 Podman/Quadlet 環境（不可逆）"
    echo "=================================="
    echo "此操作將："
    echo "- 停用使用者層級 Podman/Quadlet 相關單元（container/network/volume/pod...）"
    echo "- 一併停用並移除 TGDB 管理的 rootful（system scope）Quadlet 單元檔"
    echo "- 先移除 TGDB 管理的 Quadlet runtime 單元，並清理 rootless/rootful 全部 Podman 資源"
    echo "- 刪除所有容器、Pod、映像、網路與卷（rootless + rootful）"
    echo "- 移除使用者與 rootful 的 Podman/CNI 設定與資料目錄"
    echo "- 可選：移除系統套件 podman（以及 TGDB 自動安裝的 polkit/policykit-1）、停用 root 計時器"
    echo ""
    read -r -e -p "請輸入大寫 YES 以繼續（其餘任意鍵取消）: " confirm
    if [ "$confirm" != "YES" ]; then
        echo "已取消。"
        ui_pause
        return
    fi

    _run_podman_uninstall_flow

    echo "✅ 已嘗試將系統恢復至安裝前狀態（包含 rootless/rootful 資源與 TGDB 管理的 rootful 單元）。"
    ui_pause
}
