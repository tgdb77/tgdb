#!/bin/bash

# 系統管理：連接埠工具
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# 檢視連接埠佔用狀態
view_port_status() {
    maybe_clear
    echo "正在檢視所有監聽中的連接埠 (TCP 和 UDP)，並顯示使用該連接埠的進程（PID/程式名）..."
    if command -v ss >/dev/null 2>&1; then
        sudo ss -tulpn
    elif command -v netstat >/dev/null 2>&1; then
        sudo netstat -tulnp
    else
        echo "未找到 ss 或 netstat，請安裝 iproute2 或 net-tools。"
    fi
    pause
}
