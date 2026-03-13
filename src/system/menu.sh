#!/bin/bash

# 系統管理：主選單（可依需求客製選項/權限邏輯）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# 系統管理主選單
system_admin_menu() {
    if declare -F ui_is_interactive >/dev/null 2>&1; then
        if ! ui_is_interactive; then
            tgdb_fail "系統管理需要互動式終端（TTY）。" 2 || return $?
        fi
    fi

    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 系統管理 ❖"
        echo "=================================="
        echo "1. 修改登入密碼"
        echo "2. 用戶管理"
        echo "3. 虛擬記憶體管理"
        echo "4. 修改主機名稱"
        echo "5. 調整系統時區"
        echo "6. 檢視連接埠佔用狀態"
        echo "7. 調整 DNS 位址"
        echo "8. Cron 任務管理"
        echo "9. Linux 內核參數調整"
        echo "10. nftables 防火牆管理"
        echo "11. Fail2Ban 防禦管理"
        echo "12. SSH 服務與登入安全"
        echo "----------------------------------"
        echo "0. 返回主選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-12]: " admin_choice
        
        case $admin_choice in
            1)
                change_user_password
                ;;
            2)
                manage_users
                ;;
            3)
                manage_virtual_memory
                ;;
            4)
                change_hostname
                ;;
            5)
                manage_timezone
                ;;
            6)
                view_port_status
                ;;
            7)
                manage_dns
                ;;
            8)
                manage_cron
                ;;
            9)
                manage_kernel_parameters
                ;;
            10)
                if [ -f "$SRC_DIR/nftables.sh" ]; then
                    # shellcheck source=src/nftables.sh
                    source "$SRC_DIR/nftables.sh"
                    nftables_menu
                else
                    tgdb_err "找不到 nftables 管理模組：$SRC_DIR/nftables.sh"
                    pause
                fi
                ;;
            11)
                source "$SRC_DIR/fail2ban_manager.sh"
                fail2ban_menu
                ;;
            12)
                manage_ssh
                ;;
            0)
                return
                ;;
            *)
                echo "無效選項，請重新輸入。"
                sleep 1
                ;;
        esac
    done
}
