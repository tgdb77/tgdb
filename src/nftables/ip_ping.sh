#!/bin/bash

# nftables IP 白黑名單與 PING 控制
nftables_manage_ip_lists() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 管理 IP 白名單/黑名單 ❖"
        echo "=================================="
        echo "1. 查看白名單/黑名單"
        echo "2. 新增白名單 IP/CIDR"
        echo "3. 移除白名單 IP/CIDR"
        echo "4. 新增黑名單 IP/CIDR"
        echo "5. 移除黑名單 IP/CIDR"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-5]: " sub

        case "$sub" in
            1)
                clear
                echo "---- 白名單 (v4) ----"
                sudo nft list set inet tgdb_net whitelist_v4 2>/dev/null || echo "(無)"
                printf '\n---- 白名單 (v6) ----\n'
                sudo nft list set inet tgdb_net whitelist_v6 2>/dev/null || echo "(無)"
                printf '\n---- 黑名單 (v4) ----\n'
                sudo nft list set inet tgdb_net blacklist_v4 2>/dev/null || echo "(無)"
                printf '\n---- 黑名單 (v6) ----\n'
                sudo nft list set inet tgdb_net blacklist_v6 2>/dev/null || echo "(無)"
                echo ""
                ui_pause
                ;;
            2)
                read -r -e -p "輸入欲加入白名單的 IP 或 CIDR: " ipval
                if [ -z "$ipval" ]; then continue; fi
                local parsed
                parsed=$(_parse_ip_family_and_value "$ipval")
                local fam=${parsed%%|*}
                local val=${parsed##*|}
                local set="whitelist_v4"
                [ "$fam" = "v6" ] && set="whitelist_v6"
                # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
                if sudo nft add element inet tgdb_net "$set" { "$val" } 2>/dev/null; then
                    echo "✅ 已加入 $set: $val"
                    _persist_tgdb_table || true
                else
                    if sudo nft list set inet tgdb_net "$set" | grep -q "$val" 2>/dev/null; then
                        echo "ℹ️  $val 已存在於 $set"
                    else
                        tgdb_err "加入失敗，請確認格式與權限"
                    fi
                fi
                ui_pause
                ;;
            3)
                read -r -e -p "輸入欲自白名單移除的 IP 或 CIDR: " ipval
                if [ -z "$ipval" ]; then continue; fi
                local parsed
                parsed=$(_parse_ip_family_and_value "$ipval")
                local fam=${parsed%%|*}
                local val=${parsed##*|}
                local set="whitelist_v4"
                [ "$fam" = "v6" ] && set="whitelist_v6"
                # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
                if sudo nft delete element inet tgdb_net "$set" { "$val" } 2>/dev/null; then
                    echo "✅ 已自 $set 移除: $val"
                    _persist_tgdb_table || true
                else
                    echo "ℹ️  $val 不在 $set 中"
                fi
                ui_pause
                ;;
            4)
                read -r -e -p "輸入欲加入黑名單的 IP 或 CIDR: " ipval
                if [ -z "$ipval" ]; then continue; fi
                local parsed
                parsed=$(_parse_ip_family_and_value "$ipval")
                local fam=${parsed%%|*}
                local val=${parsed##*|}
                local set="blacklist_v4"
                [ "$fam" = "v6" ] && set="blacklist_v6"
                # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
                if sudo nft add element inet tgdb_net "$set" { "$val" } 2>/dev/null; then
                    echo "✅ 已加入 $set: $val"
                    _persist_tgdb_table || true
                else
                    if sudo nft list set inet tgdb_net "$set" | grep -q "$val" 2>/dev/null; then
                        echo "ℹ️  $val 已存在於 $set"
                    else
                        tgdb_err "加入失敗，請確認格式與權限"
                    fi
                fi
                ui_pause
                ;;
            5)
                read -r -e -p "輸入欲自黑名單移除的 IP 或 CIDR: " ipval
                if [ -z "$ipval" ]; then continue; fi
                local parsed
                parsed=$(_parse_ip_family_and_value "$ipval")
                local fam=${parsed%%|*}
                local val=${parsed##*|}
                local set="blacklist_v4"
                [ "$fam" = "v6" ] && set="blacklist_v6"
                # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
                if sudo nft delete element inet tgdb_net "$set" { "$val" } 2>/dev/null; then
                    echo "✅ 已自 $set 移除: $val"
                    _persist_tgdb_table || true
                else
                    echo "ℹ️  $val 不在 $set 中"
                fi
                ui_pause
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

# 允許/禁止 PING：透過插入/刪除 drop 規則達成
nftables_toggle_ping() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 允許/禁止 PING (ICMP/ICMPv6) ❖"
    echo "=================================="
    if ! _has_nft_cmd; then
        tgdb_fail "未安裝 nftables，請先初始化" 1 || true
        ui_pause
        return 1
    fi
    if ! _tgdb_table_exists; then
        tgdb_fail "找不到 table inet tgdb_net，請先初始化" 1 || true
        ui_pause
        return 1
    fi

    # 取得目前是否存在 PING drop 規則（用 handle 便於刪除）
    local list_out
    list_out=$(sudo nft -a list chain inet tgdb_net input 2>/dev/null)
    local h_v4 h_v6 h_v4_legacy h_v6_legacy
    h_v4=$(echo "$list_out" | awk '/tgdb-drop-ping-v4/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1)}}}')
    h_v6=$(echo "$list_out" | awk '/tgdb-drop-ping-v6/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1)}}}')
    # 舊版誤把 echo-reply 也 drop，會導致主機無法對外 ping（收不到 echo-reply）
    h_v4_legacy=$(echo "$list_out" | awk '/ip protocol icmp/ && /echo-request/ && /echo-reply/ && /drop/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1)}}}')
    h_v6_legacy=$(echo "$list_out" | awk '/icmpv6/ && /echo-request/ && /echo-reply/ && /drop/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1)}}}')

    local status="enabled"
    if [ -n "${h_v4:-}" ] || [ -n "${h_v6:-}" ] || [ -n "${h_v4_legacy:-}" ] || [ -n "${h_v6_legacy:-}" ]; then
        status="disabled"
    fi
    echo "目前 PING 狀態: $([ "$status" = "enabled" ] && echo 允許 || echo 禁止)"
    echo "1. 切換為 禁止 PING"
    echo "2. 切換為 允許 PING"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-2]: " sub

    case "$sub" in
        1)
            # 先清掉舊版/已存在的 PING drop 規則，避免誤封 echo-reply 造成「主機無法對外 ping」
            local h
            for h in ${h_v4:-} ${h_v4_legacy:-}; do
                sudo nft delete rule inet tgdb_net input handle "$h" 2>/dev/null || true
            done
            for h in ${h_v6:-} ${h_v6_legacy:-}; do
                sudo nft delete rule inet tgdb_net input handle "$h" 2>/dev/null || true
            done

            # 只禁止「外部對主機的 echo-request」，保留 echo-reply 讓主機仍可對外 ping。
            # 並排除 lo/白名單，避免影響本機與白名單運維。
            if ! sudo nft insert rule inet tgdb_net input iifname != "lo" ip saddr != @whitelist_v4 ip protocol icmp icmp type echo-request drop comment "tgdb-drop-ping-v4" 2>/dev/null; then
                sudo nft insert rule inet tgdb_net input iifname != "lo" ip protocol icmp icmp type echo-request drop comment "tgdb-drop-ping-v4" 2>/dev/null || true
            fi
            if ! sudo nft insert rule inet tgdb_net input iifname != "lo" ip6 saddr != @whitelist_v6 ip6 nexthdr icmpv6 icmpv6 type echo-request drop comment "tgdb-drop-ping-v6" 2>/dev/null; then
                sudo nft insert rule inet tgdb_net input iifname != "lo" ip6 nexthdr icmpv6 icmpv6 type echo-request drop comment "tgdb-drop-ping-v6" 2>/dev/null || true
            fi
            echo "✅ 已設定為 禁止 PING"
            _persist_tgdb_table || true
            ;;
        2)
            local h
            for h in ${h_v4:-} ${h_v4_legacy:-}; do
                sudo nft delete rule inet tgdb_net input handle "$h" 2>/dev/null || true
            done
            for h in ${h_v6:-} ${h_v6_legacy:-}; do
                sudo nft delete rule inet tgdb_net input handle "$h" 2>/dev/null || true
            done
            echo "✅ 已設定為 允許 PING"
            _persist_tgdb_table || true
            ;;
        0)
            return
            ;;
        *)
            echo "無效選項"; sleep 1
            ;;
    esac

    ui_pause
}

