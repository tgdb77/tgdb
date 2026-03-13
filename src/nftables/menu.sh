#!/bin/bash

# nftables 主選單
nftables_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "nftables 管理需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        tgdb_fail "本功能需要 sudo（目前未安裝）。" 1 || true
        ui_pause
        return 1
    fi

    if ! require_root; then
        ui_pause
        return 1
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ Nftables 防火牆管理 ❖"
        echo "=================================="
        if _has_nft_cmd; then
            local svc="未運行"
            if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nftables; then
                svc="運行中"
            fi
            if sudo nft list table inet tgdb_net >/dev/null 2>&1; then
                local sshp
                sshp=$(detect_ssh_port)
                local tcp_list udp_list ping_stat oo
                oo=$(_has_open_all_rule)
                local oo_tcp=${oo%,*}
                local oo_udp=${oo#*,}
                if [ "$oo_tcp" = "yes" ]; then
                    tcp_list="全開(規則)"
                else
                    tcp_list=$(_get_set_elements_line allowed_tcp_ports)
                fi
                if [ "$oo_udp" = "yes" ]; then
                    udp_list="全開(規則)"
                else
                    udp_list=$(_get_set_elements_line allowed_udp_ports)
                fi
                ping_stat=$(_get_ping_status)
                echo "服務: $svc | 表: inet tgdb_net ✅"
                echo "SSH 埠: $sshp"
                echo "已開放埠: TCP=[$tcp_list] | UDP=[$udp_list]"
                echo "PING 狀態: $ping_stat"
            else
                echo "服務: $svc | 表: inet tgdb_net ❌（尚未初始化）"
            fi
        else
            echo "nftables: 未安裝 ❌（請先執行 初始化）"
        fi
        echo "----------------------------------"
        echo "1. 初始化：移除舊防火牆 + 安裝 nftables + 預設規則"
        echo "2. 編輯/套用規則（/etc/nftables.conf）"
        echo "3. 開放指定埠 (TCP/UDP)"
        echo "4. 關閉指定埠 (TCP/UDP)"
        echo "5. 關閉非 SSH 埠（只保留 SSH）"
        echo "6. 開放所有埠（TCP/UDP 全開）"
        echo "7. 管理 IP 白名單/黑名單"
        echo "8. 允許/禁止 PING (ICMP/ICMPv6)"
        echo "9. 備份/還原管理"
        echo "----------------------------------"
        echo "d. 完整移除 nftables 環境"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-9]: " choice

        case "$choice" in
            1)
                nftables_init_with_default
                ;;
            2)
                nftables_edit_rules
                ;;
            3)
                nftables_open_port
                ;;
            4)
                nftables_close_port
                ;;
            5)
                nftables_close_non_ssh
                ;;
            6)
                nftables_open_all_ports
                ;;
            7)
                nftables_manage_ip_lists
                ;;
            8)
                nftables_toggle_ping
                ;;
            9)
                nftables_backup_restore_menu
                ;;
            d)
                uninstall_nftables_environment
                ;;
            0)
                return
                ;;
            *)
                echo "無效選項"; sleep 1
                ;;
        esac
    done
}
