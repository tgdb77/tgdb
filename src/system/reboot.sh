#!/bin/bash

# 系統管理：重新啟動
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

reboot_system_now() {
    maybe_clear
    local confirm_text=""

    echo "=================================="
    echo "❖ 重新啟動系統 ❖"
    echo "=================================="
    tgdb_warn "系統即將立即重新啟動，所有目前連線與執行中的服務都會中斷。"
    tgdb_warn "請確認重要工作已保存；此操作需要輸入 YES 才會執行。"
    echo "=================================="
    read -r -e -p "請輸入 YES 確認重新啟動，或按 Enter 取消: " confirm_text

    if [ "$confirm_text" != "YES" ]; then
        return 0
    fi

    echo "正在重新啟動系統..."

    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
        reboot
        return $?
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        tgdb_fail "本操作需要 sudo，但系統未安裝 sudo。" 1 || true
        pause
        return 1
    fi

    sudo reboot
}
