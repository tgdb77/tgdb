#!/bin/bash

# nftables 備份與還原
nftables_backup() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 備份 Nftables 配置 ❖"
    echo "=================================="

    require_root || { ui_pause; return 1; }

    if ! ensure_backup_dir; then
        ui_pause
        return 1
    fi

    local backup_file="$NFTABLES_BACKUP_DIR/nftables.conf"

    echo "→ 備份 /etc/nftables.conf 到 $backup_file ..."
    if [ -f /etc/nftables.conf ]; then
        sudo cp -f /etc/nftables.conf "$backup_file" && \
            echo "✅ 已備份配置檔案（覆蓋模式）"
    else
        tgdb_fail "/etc/nftables.conf 不存在" 1 || true
        ui_pause
        return 1
    fi

    ui_pause
}

# 還原備份
nftables_restore_backup() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    clear
    echo "=================================="
    echo "❖ 還原 Nftables 備份 ❖"
    echo "=================================="
    
    if ! _has_nft_cmd; then
        tgdb_fail "未安裝 nftables，無法還原" 1 || true
        ui_pause
        return 1
    fi

    require_root || { ui_pause; return 1; }

    local backup_file="$NFTABLES_BACKUP_DIR/nftables.conf"

    if [ ! -f "$backup_file" ]; then
        tgdb_fail "備份檔案不存在: $backup_file" 1 || true
        ui_pause
        return 1
    fi

    echo "→ 還原 $backup_file 到 /etc/nftables.conf ..."
    if sudo cp -f "$backup_file" /etc/nftables.conf; then
        echo "✅ 已還原配置檔案"
    else
        tgdb_fail "還原失敗" 1 || true
        ui_pause
        return 1
    fi

    echo "→ 套用規則..."
    if validate_and_apply_nftables; then
        echo "✅ 規則已套用"
    else
        tgdb_fail "套用規則失敗" 1 || true
    fi

    ui_pause
}

# 備份/還原管理選單
nftables_backup_restore_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 備份/還原管理 ❖"
        echo "=================================="
        echo "備份目錄: $NFTABLES_BACKUP_DIR"
        
        local backup_file="$NFTABLES_BACKUP_DIR/nftables.conf"
        if [ -f "$backup_file" ]; then
            local backup_time
            backup_time=$(stat -c %y "$backup_file" 2>/dev/null | cut -d'.' -f1)
            local backup_size
            backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
            echo "備份狀態: 存在 ✅"
            echo "備份時間: $backup_time"
            echo "檔案大小: $backup_size"
        else
            echo "備份狀態: 不存在 ❌"
        fi
        
        echo "----------------------------------"
        echo "1. 備份目前配置"
        echo "2. 還原備份配置"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-2]: " choice
        
        case "$choice" in
            1)
                nftables_backup
                ;;
            2)
                nftables_restore_backup
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

