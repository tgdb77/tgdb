#!/bin/bash

# nftables 埠管理
nftables_open_port() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 開放指定埠 (TCP/UDP) ❖"
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

    local port status
    if ! port="$(prompt_port_number "請輸入埠號 (1-65535)" "")"; then
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
    if ! _prompt_tcp_udp_proto proto; then
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

    local set_name="allowed_${proto}_ports"
    echo "→ 正在放行 $proto/$port ..."
    # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
    if sudo nft add element inet tgdb_net "$set_name" { "$port" } 2>/dev/null; then
        echo "✅ 已放行 $proto/$port"
    else
        if sudo nft list set inet tgdb_net "$set_name" | grep -q "{ $port }" 2>/dev/null; then
            echo "ℹ️  $proto/$port 早已在允許清單"
        else
            tgdb_fail "放行失敗，請檢查 nft set 與權限" 1 || true
            ui_pause
            return 1
        fi
    fi

    echo "→ 持久化設定..."
    _persist_tgdb_table || true

    ui_pause
}

# 關閉指定埠（TCP/UDP）
nftables_close_port() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 關閉指定埠 (TCP/UDP) ❖"
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

    local port status
    if ! port="$(prompt_port_number "請輸入埠號 (1-65535)" "")"; then
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
    if ! _prompt_tcp_udp_proto proto; then
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

    local set_name="allowed_${proto}_ports"
    echo "→ 正在關閉 $proto/$port ..."
    # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
    if sudo nft delete element inet tgdb_net "$set_name" { "$port" } 2>/dev/null; then
        echo "✅ 已關閉 $proto/$port"
    else
        echo "ℹ️  $proto/$port 不在允許清單，無需移除"
    fi

    echo "→ 持久化設定..."
    _persist_tgdb_table || true

    ui_pause
}

# 關閉非 SSH 埠：清空允許集合，僅保留基礎規則與 SSH 開放
nftables_close_non_ssh() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 關閉非 SSH 埠（僅保留 SSH） ❖"
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

    echo "此操作會清空 allowed_tcp_ports 與 allowed_udp_ports 集合，僅保留 SSH 與必要 ICMP/IPv6、已建立連線等基礎放行。"
    if ! ui_confirm_yn "確認執行？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "已取消。"
        ui_pause
        return 0
    fi

    echo "→ 清空允許集合..."
    sudo nft flush set inet tgdb_net allowed_tcp_ports 2>/dev/null || true
    sudo nft flush set inet tgdb_net allowed_udp_ports 2>/dev/null || true
    echo "✅ 已清空允許集合"

    local list_out h_tcp h_udp
    list_out=$(sudo nft -a list chain inet tgdb_net input 2>/dev/null)
    h_tcp=$(echo "$list_out" | awk '/tgdb-open-all-tcp/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1); exit}}}')
    h_udp=$(echo "$list_out" | awk '/tgdb-open-all-udp/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1); exit}}}')
    if [ -n "$h_tcp" ]; then
        sudo nft delete rule inet tgdb_net input handle "$h_tcp" 2>/dev/null || true
    fi
    if [ -n "$h_udp" ]; then
        sudo nft delete rule inet tgdb_net input handle "$h_udp" 2>/dev/null || true
    fi
    if [ -n "$h_tcp" ] || [ -n "$h_udp" ]; then
        echo "✅ 已移除全開規則"
    fi

    echo "提示：容器橋介面流量（docker0/br-*/podman0/cni-*）仍會放行與主機互通，外網非 SSH 埠已關閉。"

    echo "→ 持久化設定..."
    _persist_tgdb_table || true
    ui_pause
}

# 開放所有埠：允許 TCP/UDP 的 1-65535 於 allowed_* 集合（保留黑名單/Fail2ban 仍生效）
nftables_open_all_ports() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 開放所有埠（TCP/UDP） ❖"
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

    echo "此操作會將 1-65535 加入 allowed_tcp_ports 與 allowed_udp_ports。"
    echo "黑名單與 Fail2ban 封鎖仍會優先生效。"
    tgdb_warn "警告：等同於對公網開啟本機所有 TCP/UDP 埠，只適合短暫除錯或排障。"
    tgdb_warn "生產環境或長期運行時，請改用『開放指定埠』或『關閉非 SSH 埠』維持最小開放面。"
    if ! ui_confirm_yn "確認執行？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "已取消。"
        ui_pause
        return 0
    fi

    local ok_tcp=0 ok_udp=0
    # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
    if sudo nft add element inet tgdb_net allowed_tcp_ports { 1-65535 } 2>/dev/null; then
        echo "✅ TCP 全埠已開放（集合）"; ok_tcp=1
    fi
    # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
    if sudo nft add element inet tgdb_net allowed_udp_ports { 1-65535 } 2>/dev/null; then
        echo "✅ UDP 全埠已開放（集合）"; ok_udp=1
    fi

    if [ $ok_tcp -eq 0 ] || [ $ok_udp -eq 0 ]; then
        echo "→ 區間加入失敗，採用規則方式開放所有埠..."
        local list_out h_reject
        list_out=$(sudo nft -a list chain inet tgdb_net input 2>/dev/null)
        h_reject=$(echo "$list_out" | awk '/reject with icmpx type admin-prohibited/ {for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1); exit}}}')
        if [ -n "$h_reject" ]; then
            sudo nft delete rule inet tgdb_net input handle "$h_reject" 2>/dev/null || true
        fi
        if [ $ok_tcp -eq 0 ]; then
        sudo nft add rule inet tgdb_net input tcp dport 1-65535 accept comment "tgdb-open-all-tcp" 2>/dev/null || true
        fi
        if [ $ok_udp -eq 0 ]; then
        sudo nft add rule inet tgdb_net input udp dport 1-65535 accept comment "tgdb-open-all-udp" 2>/dev/null || true
        fi
        sudo nft add rule inet tgdb_net input reject with icmpx type admin-prohibited 2>/dev/null || true
        echo "✅ 已以規則方式放行所有 TCP/UDP 埠（黑名單/Fail2ban 仍優先）"
    fi

    echo "→ 持久化設定..."
    _persist_tgdb_table || true
    ui_pause
}

