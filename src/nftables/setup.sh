#!/bin/bash

# nftables 初始化、套用、編輯與移除
disable_legacy_firewall_services() {
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl disable --now ufw 2>/dev/null || true
        sudo systemctl disable --now firewalld 2>/dev/null || true
        sudo systemctl disable --now netfilter-persistent 2>/dev/null || true
    fi
}

remove_legacy_firewall_packages() {
    require_root || return 1

    local pkgs=()
    mapfile -t pkgs < <(pkg_role_candidates "legacy-firewall" 2>/dev/null || true)
    if [ ${#pkgs[@]} -eq 0 ]; then
        tgdb_warn "未識別的套件管理器，請手動移除 ufw/firewalld/iptables-persistent/netfilter-persistent"
        return 0
    fi

    local p
    for p in "${pkgs[@]}"; do
        pkg_purge "$p" || true
    done

    pkg_autoremove || true
}

install_nftables_pkg() {
    install_package "nftables" || return 1
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable nftables 2>/dev/null || true
        sudo systemctl restart nftables 2>/dev/null || true
    fi
}

# 預設規則生成（安全、相容 Docker/Podman/Fail2ban/IPv6）
backup_nftables_conf() {
    if [ -f /etc/nftables.conf ]; then
        if ! ensure_backup_dir; then
            tgdb_warn "無法建立備份目錄: $NFTABLES_BACKUP_DIR，略過備份。"
            return 1
        fi
        local ts backup_file
        ts=$(date +%Y%m%d%H%M%S)
        backup_file="$NFTABLES_BACKUP_DIR/nftables.conf.bak.$ts"
        if sudo cp -a /etc/nftables.conf "$backup_file"; then
            echo "已備份現有 /etc/nftables.conf -> $backup_file"
        else
            tgdb_warn "備份 /etc/nftables.conf 失敗（目標: $backup_file）"
            return 1
        fi
    fi
}

generate_default_nftables_conf() {
    local ssh_port="$1"
    [ -z "$ssh_port" ] && ssh_port=22

    # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
    sudo tee /etc/nftables.conf > /dev/null <<EOF
# 本檔由 TGDB 生成：安全預設 + Docker/Podman/Fail2ban/IPv6 友善
# 不進行全域 flush，避免破壞 iptables-nft（容器/Fail2ban 背後依賴）

table inet tgdb_net {
    # 白/黑名單與 Fail2ban 動態封鎖集合
    set whitelist_v4 { type ipv4_addr; flags interval; }
    set whitelist_v6 { type ipv6_addr; flags interval; }
    set blacklist_v4 { type ipv4_addr; flags interval; }
    set blacklist_v6 { type ipv6_addr; flags interval; }
    set f2b_ban_v4 { type ipv4_addr; flags interval; }
    set f2b_ban_v6 { type ipv6_addr; flags interval; }

    # 輔助：預留服務埠集合（允許區間元素），供後續功能擴充
    set allowed_tcp_ports { type inet_service; flags interval; }
    set allowed_udp_ports { type inet_service; flags interval; }

    # Input 鏈：用於主機入站封包
    chain input {
        type filter hook input priority 10; policy drop;

        # 1) 允許 loopback 與已建立連線（避免影響現有連線）
        iif lo accept
        ct state { established, related } accept

        # 2) 白名單優先（主動放行）
        ip saddr @whitelist_v4 accept
        ip6 saddr @whitelist_v6 accept

        # 3) Fail2ban 封鎖（若 Fail2ban 採用 set 注入）
        ip saddr @f2b_ban_v4 drop
        ip6 saddr @f2b_ban_v6 drop

        # 4) 黑名單（全域阻擋）
        ip saddr @blacklist_v4 drop
        ip6 saddr @blacklist_v6 drop

        # 5) 必要 ICMP/ICMPv6（避免 IPv6 破網、保留 PING；後續可提供開關）
        ip protocol icmp icmp type { echo-request, echo-reply, destination-unreachable, time-exceeded, parameter-problem } accept
        ip6 nexthdr icmpv6 icmpv6 type {
            echo-request, echo-reply,
            nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert,
            destination-unreachable, packet-too-big, time-exceeded, parameter-problem
        } accept

        # 6) 放行容器橋接介面進入主機（常見介面名：Docker 與 Podman）
        # 為何：避免阻斷主機與容器之間的互通，保留運維能力。
        iifname { "docker0", "br-*", "podman0", "cni-podman0", "cni-*" } accept

        # 7) 放行 SSH（偵測或預設 22）
        tcp dport $ssh_port accept

        # 7.1) 放行自訂允許的 TCP/UDP 服務埠（使用集合管理，便於後續動態增刪）
        tcp dport @allowed_tcp_ports accept
        udp dport @allowed_udp_ports accept

        # 8) 其他預設丟棄
        reject with icmpx type admin-prohibited
    }

    # Forward 鏈：避免誤傷容器/NAT（Docker/Podman），採取較寬鬆策略
    chain forward {
        type filter hook forward priority 10; policy accept;
        # 可依實務需求改為 policy drop 並顯式放行 docker0/br-*/podman0/cni-*（後續功能階段化）
    }

    # Output 鏈：一般情況允許主機對外
    chain output {
        type filter hook output priority 10; policy accept;
    }

}
EOF
}

validate_and_apply_nftables() {
    if sudo nft -c -f /etc/nftables.conf >/dev/null 2>&1; then
        echo "✅ 規則語法檢驗通過"
    else
        tgdb_fail "規則語法檢驗失敗，已停止套用，請檢查 /etc/nftables.conf" 1 || true
        return 1
    fi

    if sudo nft list table inet tgdb_net >/dev/null 2>&1; then
        sudo nft delete table inet tgdb_net 2>/dev/null || true
    fi
    sudo nft -f /etc/nftables.conf && echo "✅ 已套用 inet tgdb_net 規則"

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable nftables 2>/dev/null || true
        systemctl is-active --quiet nftables || sudo systemctl start nftables 2>/dev/null || true
    fi
}

# 供 SSH 模組呼叫：更新 nftables 中 SSH 埠並立即套用
nftables_update_ssh_port() {
    local current_port="$1"
    local new_port="$2"

    if [ -z "$current_port" ] || [ -z "$new_port" ]; then
        echo "ℹ️ 未提供完整的舊/新 SSH 埠，略過 nftables 規則自動更新。"
        return 0
    fi

    if ! _has_nft_cmd; then
        echo "ℹ️ 系統未安裝 nftables，略過防火牆規則自動更新。"
        return 0
    fi

    if [ ! -f /etc/nftables.conf ]; then
        echo "ℹ️ 未找到 /etc/nftables.conf，略過自動更新，請手動確認防火牆規則。"
        return 0
    fi

    if ! ensure_backup_dir; then
        tgdb_warn "無法建立備份目錄: $NFTABLES_BACKUP_DIR，為安全起見略過自動更新。"
        return 1
    fi

    local ts bak
    ts=$(date +%Y%m%d%H%M%S)
    bak="$NFTABLES_BACKUP_DIR/nftables.conf.ssh_port.$ts"

    if sudo cp -a /etc/nftables.conf "$bak"; then
        echo "🗂️ 已備份 /etc/nftables.conf -> $bak"
    else
        tgdb_warn "無法備份 /etc/nftables.conf，為安全起見略過自動更新。"
        return 1
    fi

    echo "→ 嘗試在 nftables 規則中將 SSH 埠由 $current_port 調整為 $new_port..."

    if ! sudo sed -E -i "s/^([[:space:]]*tcp[[:space:]]+dport[[:space:]]+)$current_port([[:space:]]+accept.*)$/\1$new_port\2/" /etc/nftables.conf; then
        tgdb_warn "無法自動更新防火牆設定檔，請手動修改。（備份於：$bak）"
        return 1
    fi

    if ! grep -Eq "tcp[[:space:]]+dport[[:space:]]+${new_port}[[:space:]]+accept" /etc/nftables.conf; then
        tgdb_warn "未在 /etc/nftables.conf 中找到符合預期格式的 SSH 規則，可能使用自訂寫法，請手動檢查。（備份於：$bak）"
        return 1
    fi

    if validate_and_apply_nftables; then
        echo "✅ 已重新套用 nftables 規則，新的 SSH 埠應已放行。"
        return 0
    else
        tgdb_warn "規則套用失敗，請檢查 /etc/nftables.conf，必要時可手動還原備份：$bak"
        return 1
    fi
}

# 導引流程（第一階段：移除舊防火牆 + 安裝 + 預設規則）

nftables_allow_default_ports_cli() {
    # 預設額外放行：TCP 80/443、UDP 443（SSH 由規則本身處理）
    if ! _has_nft_cmd; then
        tgdb_fail "未安裝 nftables，無法設定放行埠。" 1 || true
        return 1
    fi
    if ! _tgdb_table_exists; then
        tgdb_fail "找不到 table inet tgdb_net，請先初始化。" 1 || true
        return 1
    fi

    local ok=1
    # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
    sudo nft add element inet tgdb_net allowed_tcp_ports { 80, 443 } 2>/dev/null || true
    # shellcheck disable=SC1083
    sudo nft add element inet tgdb_net allowed_udp_ports { 443 } 2>/dev/null || true

    if ! sudo nft list set inet tgdb_net allowed_tcp_ports 2>/dev/null | grep -Eq '(^|[^0-9])80([^0-9]|$)' || \
       ! sudo nft list set inet tgdb_net allowed_tcp_ports 2>/dev/null | grep -Eq '(^|[^0-9])443([^0-9]|$)'; then
        ok=0
    fi
    if ! sudo nft list set inet tgdb_net allowed_udp_ports 2>/dev/null | grep -Eq '(^|[^0-9])443([^0-9]|$)'; then
        ok=0
    fi

    if [ "$ok" -ne 1 ]; then
        tgdb_fail "無法確認預設放行埠已寫入 nftables set，請手動檢查。" 1 || true
        return 1
    fi

    echo "✅ 已放行預設埠：TCP 80/443、UDP 443"
    echo "→ 持久化設定..."
    _persist_tgdb_table || true
    return 0
}

nftables_init_with_default_cli() {
    echo "=================================="
    echo "❖ 初始化 nftables 並套用預設規則（CLI）❖"
    echo "=================================="
    echo "此流程將："
    echo "1) 停用並移除 ufw/firewalld/iptables-persistent/netfilter-persistent（若存在）"
    echo "2) 安裝並啟用 nftables 服務"
    echo "3) 以安全預設生成 /etc/nftables.conf（相容 Docker/Podman/Fail2ban/IPv6）"
    echo "4) 檢驗規則並套用"
    echo "5) 額外放行 TCP 80/443、UDP 443"
    echo "----------------------------------"

    require_root || return 1

    local ssh_port
    ssh_port=$(detect_ssh_port)
    echo "偵測 SSH 連接埠: $ssh_port"

    echo "→ 停用舊防火牆服務..."
    disable_legacy_firewall_services

    echo "→ 移除舊防火牆套件..."
    remove_legacy_firewall_packages

    echo "→ 安裝 nftables..."
    if ! install_nftables_pkg; then
        tgdb_fail "安裝 nftables 失敗" 1 || true
        return 1
    fi

    echo "→ 備份現有 /etc/nftables.conf（若存在）..."
    backup_nftables_conf || true

    echo "→ 生成預設規則（包含 SSH:$ssh_port / Docker/Podman / Fail2ban / IPv6）..."
    generate_default_nftables_conf "$ssh_port"

    echo "→ 檢驗並套用規則..."
    if ! validate_and_apply_nftables; then
        tgdb_fail "初始化失敗，請檢查設定" 1 || true
        return 1
    fi

    if ! nftables_allow_default_ports_cli; then
        return 1
    fi

    echo "✅ 初始化完成"
    return 0
}

nftables_init_with_default() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 初始化 nftables 並套用預設規則 ❖"
    echo "=================================="
    echo "此流程將："
    echo "1) 停用並移除 ufw/firewalld/iptables-persistent/netfilter-persistent（若存在）"
    echo "2) 安裝並啟用 nftables 服務"
    echo "3) 以安全預設生成 /etc/nftables.conf（相容 Docker/Podman/Fail2ban/IPv6）"
    echo "4) 檢驗規則並套用"
    echo "----------------------------------"

    require_root || { ui_pause; return 1; }

    local ssh_port
    ssh_port=$(detect_ssh_port)
    echo "偵測 SSH 連接埠: $ssh_port"

    if ! ui_confirm_yn "是否繼續進行？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "已取消。"
        ui_pause
        return 0
    fi

    echo "→ 停用舊防火牆服務..."
    disable_legacy_firewall_services

    echo "→ 移除舊防火牆套件..."
    remove_legacy_firewall_packages

    echo "→ 安裝 nftables..."
    if ! install_nftables_pkg; then
        tgdb_fail "安裝 nftables 失敗" 1 || true
        ui_pause
        return 1
    fi

    echo "→ 備份現有 /etc/nftables.conf（若存在）..."
    backup_nftables_conf

    echo "→ 生成預設規則（包含 SSH:$ssh_port / Docker/Podman / Fail2ban / IPv6）..."
    generate_default_nftables_conf "$ssh_port"

    echo "→ 檢驗並套用規則..."
    if validate_and_apply_nftables; then
        echo "✅ 初始化完成"
    else
        tgdb_fail "初始化失敗，請檢查設定" 1 || true
    fi

    ui_pause
}

# 簡易選單（後續會擴充完整功能項）

nftables_edit_rules() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 編輯/套用 nftables 規則 ❖"
    echo "=================================="
    if ! _has_nft_cmd; then
        tgdb_fail "未安裝 nftables，請先執行初始化（選單 1）" 1 || true
        ui_pause
        return 1
    fi

    require_root || { ui_pause; return 1; }

    echo "----------------------------------"
    echo "安全提醒："
    echo "- 請避免在檔案中使用 'flush ruleset'，以免清空其他系統表（如 容器/Docker/Podman/Fail2ban 相關）"
    echo "- 請保留 SSH 連接埠放行，避免鎖死遠端管理（目前偵測: $(detect_ssh_port)）"
    echo "- 本工具預設只管理 table 'inet tgdb_net'，降低與其他表衝突風險"
    echo "----------------------------------"
    ui_pause "已閱讀安全提醒，按任意鍵繼續編輯..."

    if [ ! -f /etc/nftables.conf ]; then
        echo "→ 未發現 /etc/nftables.conf，嘗試從現有 inet tgdb_net 匯出..."
        if sudo nft -s list table inet tgdb_net >/dev/null 2>&1; then
            if sudo nft -s list table inet tgdb_net | sudo tee /etc/nftables.conf >/dev/null; then
                echo "✅ 已從 inet tgdb_net 匯出至 /etc/nftables.conf"
            else
                tgdb_warn "匯出失敗，改為生成安全預設..."
                local ssh_port
                ssh_port=$(detect_ssh_port)
                generate_default_nftables_conf "$ssh_port"
            fi
        else
            echo "→ 尚未建立 inet tgdb_net，生成安全預設..."
            local ssh_port
            ssh_port=$(detect_ssh_port)
            generate_default_nftables_conf "$ssh_port"
        fi
    fi

    local ts bak
    ts=$(date +%Y%m%d%H%M%S)
    bak=""
    if ensure_backup_dir && [ -f /etc/nftables.conf ]; then
        bak="$NFTABLES_BACKUP_DIR/nftables.conf.edit.$ts"
        if sudo cp -a /etc/nftables.conf "$bak"; then
            echo "🗂️ 已建立暫存備份（編輯結束後將自動刪除）。"
        else
            tgdb_warn "無法建立暫存備份，將略過自動還原功能。"
            bak=""
        fi
    else
        echo "ℹ️ 未建立暫存備份，將直接在 /etc/nftables.conf 上編輯。"
    fi

    if ensure_editor; then
        echo "→ 啟動編輯器: $EDITOR（完成後儲存並離開）"
        sudo -E "$EDITOR" /etc/nftables.conf
    else
        tgdb_warn "找不到可用編輯器（nano/vim/vi），請手動編輯 /etc/nftables.conf 後繼續"
        ui_pause "編輯完成後按任意鍵繼續..."
    fi

    if sudo grep -Eq '^[[:space:]]*flush[[:space:]]+ruleset' /etc/nftables.conf 2>/dev/null; then
        tgdb_warn "偵測到檔案包含 'flush ruleset'，這可能清空其他表/鏈，與 容器/Docker/Podman/Fail2ban 衝突"
        if ! ui_confirm_yn "仍要繼續驗證與套用？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            echo "已取消。"
            if [ -n "$bak" ] && [ -f "$bak" ]; then
                echo "→ 將 /etc/nftables.conf 還原為編輯前狀態..."
                if sudo cp -a "$bak" /etc/nftables.conf; then
                    echo "✅ 已還原 /etc/nftables.conf"
                else
                    tgdb_warn "還原 /etc/nftables.conf 失敗，請手動檢查。"
                fi
            fi
            ui_pause
            if [ -n "$bak" ] && [ -f "$bak" ]; then
                sudo rm -f "$bak" 2>/dev/null || true
            fi
            return 0
        fi
    fi

    echo "→ 驗證語法..."
    if ! sudo nft -c -f /etc/nftables.conf >/dev/null 2>&1; then
        tgdb_fail "規則語法檢驗失敗。" 1 || true
        if [ -n "$bak" ] && [ -f "$bak" ]; then
            echo "→ 還原 /etc/nftables.conf 至編輯前狀態..."
            if sudo cp -a "$bak" /etc/nftables.conf; then
                echo "✅ 已還原 /etc/nftables.conf"
            else
                tgdb_warn "還原 /etc/nftables.conf 失敗，請手動檢查。"
            fi
        else
            echo "ℹ️ 因未建立暫存備份，/etc/nftables.conf 保持目前內容。"
        fi
        ui_pause
        # 清理暫存備份檔
        if [ -n "$bak" ] && [ -f "$bak" ]; then
            sudo rm -f "$bak" 2>/dev/null || true
        fi
        return 1
    fi
    echo "✅ 規則語法檢驗通過"

    if ui_confirm_yn "是否立即套用變更到系統？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "→ 套用變更..."
        if validate_and_apply_nftables; then
            echo "✅ 已套用新規則"
        else
            tgdb_fail "套用失敗，可手動檢視 /etc/nftables.conf。" 1 || true
        fi
    else
        echo "已跳過套用，將還原 /etc/nftables.conf 至編輯前狀態..."
        if [ -n "$bak" ] && [ -f "$bak" ]; then
            if sudo cp -a "$bak" /etc/nftables.conf; then
                echo "✅ 已還原 /etc/nftables.conf"
            else
                tgdb_warn "還原 /etc/nftables.conf 失敗，請手動檢查。"
            fi
        else
            echo "ℹ️ 未找到備份檔，/etc/nftables.conf 將維持目前內容。"
        fi
    fi

    if [ -n "$bak" ] && [ -f "$bak" ]; then
        sudo rm -f "$bak" 2>/dev/null || true
    fi

    ui_pause
}


uninstall_nftables_environment() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    tgdb_warn "完整移除 nftables 環境（危險）"
    echo "=================================="
    echo "此操作將嘗試："
    echo "- 停用並關閉 nftables 系統服務"
    echo "- 刪除 TGDB 專用 table inet tgdb_net"
    echo "- 刪除 /etc/nftables.conf（會先建立備份）"
    echo "- 移除 nftables 套件與相依套件"
    echo ""
    echo "注意：執行後系統可能不再有任何防火牆保護，"
    echo "如需防護請自行安裝並啟用其他防火牆（例如 ufw/firewalld）。"
    echo "本工具不會自動恢復先前已移除的 ufw/firewalld 等舊防火牆。"
    echo "----------------------------------"

    require_root || { ui_pause; return 1; }

    read -r -e -p "請輸入大寫 YES 以繼續（其餘任意鍵取消）: " confirm
    if [ "$confirm" != "YES" ]; then
        echo "已取消。"
        ui_pause
        return 0
    fi

    echo "→ 停用 nftables 系統服務（若存在）..."
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl disable --now nftables 2>/dev/null || true
    fi

    echo "→ 移除 TGDB 專用 table inet tgdb_net ..."
    if sudo nft list table inet tgdb_net >/dev/null 2>&1; then
        sudo nft delete table inet tgdb_net 2>/dev/null || true
        echo "✅ 已刪除 table inet tgdb_net"
    else
        echo "ℹ️  未檢測到 table inet tgdb_net（可能已不存在）"
    fi

    if [ -f /etc/nftables.conf ]; then
        echo "→ 偵測到 /etc/nftables.conf，將建立備份並刪除..."
        local ts backup_path
        ts=$(date +%Y%m%d%H%M%S)
        backup_path="/etc/nftables.conf.tgdb-removed.$ts"
        if sudo cp -a /etc/nftables.conf "$backup_path"; then
            echo "🗂️ 已備份至: $backup_path"
            sudo rm -f /etc/nftables.conf 2>/dev/null || true
            echo "✅ 已刪除 /etc/nftables.conf（備份仍保留）"
        else
            tgdb_warn "備份 /etc/nftables.conf 失敗，為安全起見不進行刪除，請手動檢查。"
        fi
    fi

    echo "----------------------------------"
    echo "→ 透過套件管理器移除 nftables..."
    if ! pkg_purge "nftables"; then
        tgdb_warn "套件移除指令執行失敗，請手動檢查。"
    fi
    pkg_autoremove || true

    echo "✅ 完整移除流程已執行（請依需要另外配置防火牆）。"
    ui_pause
}
