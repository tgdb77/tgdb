#!/bin/bash

# nftables Tailnet 服務埠轉發
_tgdb_ts_fwd_chain_ensure() {
    # 確保 Tailnet 轉發相關 set/chain/rule 存在（僅管理 table inet tgdb_net）。
    if ! _has_nft_cmd; then
        tgdb_fail "未安裝 nftables，無法設定 Tailnet 轉發。" 1 || true
        return 1
    fi
    if ! _tgdb_table_exists; then
        tgdb_fail "找不到 table inet tgdb_net，請先到「nftables 管理」初始化。" 1 || true
        return 1
    fi

    # 重要：若要 DNAT 到 127.0.0.1，通常需要允許把 127/8 視為可路由到本機。
    # 只設 tailscale0 在部分系統上仍可能不足，因此一併設 all 與 tailscale0。
    # 否則可能被內核視為 martian packet 而丟棄，外部表現多為 timeout/連不上。
    sudo sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null 2>&1 || true
    sudo sysctl -w net.ipv4.conf.tailscale0.route_localnet=1 >/dev/null 2>&1 || true

    # sets
    if ! sudo nft list set inet tgdb_net ts_fwd_tcp_ports >/dev/null 2>&1; then
        sudo nft add set inet tgdb_net ts_fwd_tcp_ports '{ type inet_service; flags interval; }' 2>/dev/null || true
    fi
    if ! sudo nft list set inet tgdb_net ts_fwd_udp_ports >/dev/null 2>&1; then
        sudo nft add set inet tgdb_net ts_fwd_udp_ports '{ type inet_service; flags interval; }' 2>/dev/null || true
    fi

    # input allow rules (tailscale0 only)
    local in_list
    in_list="$(sudo nft -a list chain inet tgdb_net input 2>/dev/null || true)"
    local need_allow_tcp=0 need_allow_udp=0
    if ! echo "$in_list" | grep -F "tgdb-ts-allow-tcp" >/dev/null 2>&1; then
        need_allow_tcp=1
    fi
    if ! echo "$in_list" | grep -F "tgdb-ts-allow-udp" >/dev/null 2>&1; then
        need_allow_udp=1
    fi
    if [ "$need_allow_tcp" -eq 1 ] || [ "$need_allow_udp" -eq 1 ]; then
        # 重要：避免把 allow 規則插到最前面而繞過黑名單/Fail2ban，採用「暫時移除 reject → 追加 allow → 補回 reject」。
        local h_reject
        h_reject=$(echo "$in_list" | awk '/reject with icmpx/ && /admin-prohibited/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1); exit}}}')
        if [ -n "${h_reject:-}" ]; then
            sudo nft delete rule inet tgdb_net input handle "$h_reject" 2>/dev/null || true
        fi

        if [ "$need_allow_tcp" -eq 1 ]; then
            sudo nft add rule inet tgdb_net input iifname "tailscale0" tcp dport @ts_fwd_tcp_ports accept comment "tgdb-ts-allow-tcp" 2>/dev/null || true
        fi
        if [ "$need_allow_udp" -eq 1 ]; then
            sudo nft add rule inet tgdb_net input iifname "tailscale0" udp dport @ts_fwd_udp_ports accept comment "tgdb-ts-allow-udp" 2>/dev/null || true
        fi

        if [ -n "${h_reject:-}" ]; then
            sudo nft add rule inet tgdb_net input reject with icmpx type admin-prohibited 2>/dev/null || true
        fi
    fi
    in_list="$(sudo nft -a list chain inet tgdb_net input 2>/dev/null || true)"
    if ! echo "$in_list" | grep -F "tgdb-ts-allow-tcp" >/dev/null 2>&1 || \
       ! echo "$in_list" | grep -F "tgdb-ts-allow-udp" >/dev/null 2>&1; then
        tgdb_fail "建立 Tailnet 放行規則失敗（缺少 input accept 規則）。" 1 || true
        return 1
    fi

    # nat prerouting / postrouting chains
    if ! sudo nft list chain inet tgdb_net ts_prerouting >/dev/null 2>&1; then
        sudo nft add chain inet tgdb_net ts_prerouting '{ type nat hook prerouting priority -100; policy accept; }' 2>/dev/null || true
    fi
    if ! sudo nft list chain inet tgdb_net ts_postrouting >/dev/null 2>&1; then
        sudo nft add chain inet tgdb_net ts_postrouting '{ type nat hook postrouting priority 100; policy accept; }' 2>/dev/null || true
    fi

    local pre_list
    pre_list="$(sudo nft -a list chain inet tgdb_net ts_prerouting 2>/dev/null || true)"
    local post_list
    post_list="$(sudo nft -a list chain inet tgdb_net ts_postrouting 2>/dev/null || true)"
    # 先移除舊版 redirect 規則（redirect 會導向本機「該介面 IP」，若服務只綁 127.0.0.1，外部仍會 Connection refused）。
    local h_fwd_tcp h_fwd_udp h_snat_v4
    h_fwd_tcp=$(echo "$pre_list" | awk '/tgdb-ts-fwd-tcp/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1); exit}}}')
    h_fwd_udp=$(echo "$pre_list" | awk '/tgdb-ts-fwd-udp/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1); exit}}}')
    h_snat_v4=$(echo "$post_list" | awk '/tgdb-ts-snat-v4/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1); exit}}}')
    if [ -n "${h_fwd_tcp:-}" ]; then
        sudo nft delete rule inet tgdb_net ts_prerouting handle "$h_fwd_tcp" 2>/dev/null || true
    fi
    if [ -n "${h_fwd_udp:-}" ]; then
        sudo nft delete rule inet tgdb_net ts_prerouting handle "$h_fwd_udp" 2>/dev/null || true
    fi
    if [ -n "${h_snat_v4:-}" ]; then
        sudo nft delete rule inet tgdb_net ts_postrouting handle "$h_snat_v4" 2>/dev/null || true
    fi

    # 建立新版 DNAT 規則：僅針對 IPv4（ip protocol），轉到 127.0.0.1（保留原 dport）。
    # 若你的客戶端走 IPv6（fd7a:...），服務仍需另外處理（例如服務也綁定 ::1 或改用反代）。
    sudo nft add rule inet tgdb_net ts_prerouting iifname "tailscale0" fib daddr type local ip protocol tcp tcp dport @ts_fwd_tcp_ports dnat to 127.0.0.1 comment "tgdb-ts-fwd-tcp" 2>/dev/null || true
    sudo nft add rule inet tgdb_net ts_prerouting iifname "tailscale0" fib daddr type local ip protocol udp udp dport @ts_fwd_udp_ports dnat to 127.0.0.1 comment "tgdb-ts-fwd-udp" 2>/dev/null || true
    # 補上回程 SNAT：避免回應封包帶著 127.0.0.1 當來源位址離開 tailscale0。
    sudo nft add rule inet tgdb_net ts_postrouting ct status dnat oifname "tailscale0" ip saddr 127.0.0.1 masquerade comment "tgdb-ts-snat-v4" 2>/dev/null || true

    # 最後確認（避免靜默失敗）
    if ! sudo nft list set inet tgdb_net ts_fwd_tcp_ports >/dev/null 2>&1 || \
       ! sudo nft list set inet tgdb_net ts_fwd_udp_ports >/dev/null 2>&1; then
        tgdb_fail "建立 Tailnet 轉發集合失敗（ts_fwd_tcp_ports/ts_fwd_udp_ports）。" 1 || true
        return 1
    fi
    if ! sudo nft list chain inet tgdb_net ts_prerouting >/dev/null 2>&1; then
        tgdb_fail "建立 Tailnet 轉發鏈失敗（chain ts_prerouting）。你的 nftables 版本可能不支援 inet/nat，請改用 socat/systemd 轉發或改用 ip/ip6 nat 表。" 1 || true
        return 1
    fi
    if ! sudo nft list chain inet tgdb_net ts_postrouting >/dev/null 2>&1; then
        tgdb_fail "建立 Tailnet 轉發鏈失敗（chain ts_postrouting）。你的 nftables 版本可能不支援 inet/nat，請改用 socat/systemd 轉發或改用 ip/ip6 nat 表。" 1 || true
        return 1
    fi
    pre_list="$(sudo nft -a list chain inet tgdb_net ts_prerouting 2>/dev/null || true)"
    post_list="$(sudo nft -a list chain inet tgdb_net ts_postrouting 2>/dev/null || true)"
    if ! echo "$pre_list" | grep -F "tgdb-ts-fwd-tcp" >/dev/null 2>&1 || \
       ! echo "$pre_list" | grep -F "tgdb-ts-fwd-udp" >/dev/null 2>&1; then
        tgdb_fail "建立 Tailnet 轉發規則失敗（缺少 DNAT 規則）。" 1 || true
        return 1
    fi
    if ! echo "$post_list" | grep -F "tgdb-ts-snat-v4" >/dev/null 2>&1; then
        tgdb_fail "建立 Tailnet 轉發規則失敗（缺少回程 SNAT 規則）。" 1 || true
        return 1
    fi

    return 0
}

_prompt_tcp_udp_both_proto() {
    local out_var="$1"
    if [ -z "${out_var:-}" ]; then
        tgdb_fail "_prompt_tcp_udp_both_proto 參數不足：<out_var>" 1 || true
        return 1
    fi

    local idx
    echo "請選擇協定："
    echo "1. TCP+UDP（預設）"
    echo "2. TCP"
    echo "3. UDP"
    if ! ui_prompt_index idx "請輸入選擇 [1-3] (預設 1，輸入 0 取消): " 1 3 1 0; then
        return $?
    fi

    case "$idx" in
        1) printf -v "$out_var" '%s' "both" ;;
        2) printf -v "$out_var" '%s' "tcp" ;;
        3) printf -v "$out_var" '%s' "udp" ;;
        *) return 1 ;;
    esac
    return 0
}

nftables_ts_forward_add_port() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 新增 Tailnet 服務埠轉發（TCP/UDP）❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }

    local port status
    if ! port="$(prompt_port_number "請輸入要轉發的埠號 (1-65535)" "")"; then
        status=$?
        if [ "$status" -eq 2 ]; then
            echo "已取消。"
            ui_pause
            return 0
        fi
        tgdb_err "取得埠號失敗"
        ui_pause
        return 1
    fi

    local proto
    if ! _prompt_tcp_udp_both_proto proto; then
        status=$?
        if [ "$status" -eq 2 ]; then
            echo "已取消。"
            ui_pause
            return 0
        fi
        tgdb_err "取得協定失敗"
        ui_pause
        return 1
    fi

    if ! _tgdb_ts_fwd_chain_ensure; then
        ui_pause
        return 1
    fi

    local ok=1
    if [ "$proto" = "tcp" ] || [ "$proto" = "both" ]; then
        # shellcheck disable=SC1083
        sudo nft add element inet tgdb_net ts_fwd_tcp_ports { "$port" } 2>/dev/null || true
        if ! sudo nft list set inet tgdb_net ts_fwd_tcp_ports 2>/dev/null | grep -Eq "(^|[^0-9])${port}([^0-9]|$)"; then
            ok=0
        fi
    fi
    if [ "$proto" = "udp" ] || [ "$proto" = "both" ]; then
        # shellcheck disable=SC1083
        sudo nft add element inet tgdb_net ts_fwd_udp_ports { "$port" } 2>/dev/null || true
        if ! sudo nft list set inet tgdb_net ts_fwd_udp_ports 2>/dev/null | grep -Eq "(^|[^0-9])${port}([^0-9]|$)"; then
            ok=0
        fi
    fi

    if [ "$ok" -ne 1 ]; then
        tgdb_fail "新增轉發埠失敗，請檢查 nftables 版本/權限與規則狀態。" 1 || true
        ui_pause
        return 1
    fi

    echo "✅ 已新增 Tailnet 轉發：$proto/$port -> 127.0.0.1:$port"
    echo "ℹ️ 請使用本機的 Tailnet IPv4（通常是 100.x.y.z）測試，不要先用節點名稱 / IPv6。"
    echo "→ 持久化設定..."
    _persist_tgdb_table || true
    ui_pause
    return 0
}

nftables_ts_forward_remove_port() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 移除 Tailnet 服務埠轉發（TCP/UDP）❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }

    local port status
    if ! port="$(prompt_port_number "請輸入要移除的轉發埠號 (1-65535)" "")"; then
        status=$?
        if [ "$status" -eq 2 ]; then
            echo "已取消。"
            ui_pause
            return 0
        fi
        tgdb_err "取得埠號失敗"
        ui_pause
        return 1
    fi

    local proto
    if ! _prompt_tcp_udp_both_proto proto; then
        status=$?
        if [ "$status" -eq 2 ]; then
            echo "已取消。"
            ui_pause
            return 0
        fi
        tgdb_err "取得協定失敗"
        ui_pause
        return 1
    fi

    if ! _tgdb_ts_fwd_chain_ensure; then
        ui_pause
        return 1
    fi

    if [ "$proto" = "tcp" ] || [ "$proto" = "both" ]; then
        # shellcheck disable=SC1083
        sudo nft delete element inet tgdb_net ts_fwd_tcp_ports { "$port" } 2>/dev/null || true
    fi
    if [ "$proto" = "udp" ] || [ "$proto" = "both" ]; then
        # shellcheck disable=SC1083
        sudo nft delete element inet tgdb_net ts_fwd_udp_ports { "$port" } 2>/dev/null || true
    fi

    echo "✅ 已移除 Tailnet 轉發：$proto/$port（若原本不存在則視為已完成）"
    echo "→ 持久化設定..."
    _persist_tgdb_table || true
    ui_pause
    return 0
}

nftables_ts_forward_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    require_root || { ui_pause; return 1; }

    while true; do
        clear
        echo "=================================="
        echo "❖ Tailnet 服務埠轉發（tailscale0 -> 127.0.0.1）❖"
        echo "=================================="

        if _has_nft_cmd && _tgdb_table_exists; then
            local tcp_list udp_list
            tcp_list="$(_get_set_elements_line ts_fwd_tcp_ports)"
            udp_list="$(_get_set_elements_line ts_fwd_udp_ports)"
            echo "目前 TCP 轉發埠：$tcp_list"
            echo "目前 UDP 轉發埠：$udp_list"
        else
            echo "目前 TCP 轉發埠：未初始化（請先到 nftables 管理初始化）"
            echo "目前 UDP 轉發埠：未初始化（請先到 nftables 管理初始化）"
        fi

        echo "----------------------------------"
        echo "1. 新增轉發埠（TCP/UDP）"
        echo "2. 移除轉發埠（TCP/UDP）"
        echo "----------------------------------"
        echo "0. 返回上一層"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-2]: " choice

        case "$choice" in
            1) nftables_ts_forward_add_port || true ;;
            2) nftables_ts_forward_remove_port || true ;;
            0) return 0 ;;
            *) echo "無效選項，請重新輸入。"; sleep 1 ;;
        esac
    done
}
