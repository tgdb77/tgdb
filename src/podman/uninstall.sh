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

_disable_user_podman_units() {
    _systemctl_user_try disable --now -- podman-auto-update.timer podman-auto-update.service || true

    local unit
    while IFS= read -r unit; do
        [ -n "$unit" ] || continue
        _unit_try_disable_now "$unit"
    done < <(_list_user_units container network volume pod device kube image)

    _systemctl_user_try reset-failed || true
}

_purge_user_quadlet_files() {
    local user_units_dir
    user_units_dir="$(rm_user_units_dir)"
    [ -n "$user_units_dir" ] || return 0
    [ -d "$user_units_dir" ] || return 0

    find "$user_units_dir" -maxdepth 1 \( -type f -o -type l \) -exec rm -f -- {} + 2>/dev/null || true
    _systemctl_user_try daemon-reload || true
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

_purge_user_podman_dirs() {
    _safe_rm_rf "$HOME/.config/containers"
    _safe_rm_rf "$HOME/.local/share/containers"
    _safe_rm_rf "$HOME/.cache/containers"
    _safe_rm_rf "$HOME/.config/cni"
    _safe_rm_rf "$HOME/.local/share/cni"
    _safe_rm_rf "${XDG_RUNTIME_DIR:-/run/user/$UID}/containers"
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
    echo "- 移除所有 Quadlet 單元檔（*.container/*.network/*.volume/*.pod/*.kube/*.device/*.image）"
    echo "- 刪除所有容器、Pod、映像、網路與卷（rootless）"
    echo "- 移除使用者 podman 設定與資料目錄 (~/.config|~/.local/share|~/.cache/containers)"
    echo "- 可選：移除系統套件 podman（以及 TGDB 自動安裝的 polkit/policykit-1）、停用 root 計時器"
    echo ""
    read -r -e -p "請輸入大寫 YES 以繼續（其餘任意鍵取消）: " confirm
    if [ "$confirm" != "YES" ]; then
        echo "已取消。"
        ui_pause
        return
    fi

    echo "→ 停用使用者層級 Podman 相關服務..."
    _disable_user_podman_units

    echo "→ 刪除 Quadlet 單元檔..."
    _purge_user_quadlet_files

    echo "→ 刪除 rootless Podman 全部資源..."
    _nuke_rootless_podman_resources

    echo "→ 清理使用者 Podman 目錄..."
    _purge_user_podman_dirs

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

    echo "✅ 已嘗試將系統恢復至安裝前狀態（rootless 範疇）。"
    ui_pause
}
