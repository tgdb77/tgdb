#!/bin/bash

# Podman：容器自動更新（podman auto-update）
# 說明：互動菜單已集中於 src/podman/menu.sh，此檔案保留底層輔助函式。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_podman_auto_update_timer_enable() {
    if ! command -v systemctl >/dev/null 2>&1; then
        tgdb_fail "找不到 systemctl，無法啟用 podman-auto-update.timer" 1 || return $?
    fi
    _enable_user_systemd_and_linger || true
    if _systemctl_user_try enable --now -- podman-auto-update.timer; then
        echo "✅ 已啟用：podman-auto-update.timer"
        return 0
    fi
    tgdb_warn "無法啟用 podman-auto-update.timer（可能未安裝或系統不支援 user systemd）"
    return 1
}

_podman_auto_update_timer_disable() {
    if ! command -v systemctl >/dev/null 2>&1; then
        tgdb_fail "找不到 systemctl，無法停用 podman-auto-update.timer" 1 || return $?
    fi
    _systemctl_user_try disable --now -- podman-auto-update.timer podman-auto-update.service || true
    echo "✅ 已嘗試停用：podman-auto-update.timer"
}
