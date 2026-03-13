#!/bin/bash

# 系統管理：通用輔助函式（供 src/system_admin.sh 與各子模組使用）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# 通用輔助：在非互動環境避免 clear/read 堵塞
pause() {
    if declare -F ui_pause >/dev/null 2>&1; then
        ui_pause "按任意鍵返回..."
    fi
    return 0
}

maybe_clear() {
    if declare -F ui_is_interactive >/dev/null 2>&1; then
        ui_is_interactive || return 0
        clear
        return 0
    fi
    [ -t 1 ] && clear
}

system_admin_confirm_yn() {
    local prompt="$1"
    local default="${2:-Y}"

    if ! declare -F ui_confirm_yn >/dev/null 2>&1; then
        tgdb_fail "缺少共用確認函式 ui_confirm_yn，請確認已載入 src/core/ui.sh（通常透過 src/core/utils.sh）。" 2 || return $?
    fi

    ui_confirm_yn "$prompt" "$default"
    return $?
}

# 取得系統管理員群組
get_admin_group() {
    if getent group sudo >/dev/null 2>&1; then
        echo sudo
    elif getent group wheel >/dev/null 2>&1; then
        echo wheel
    else
        echo sudo
    fi
}
