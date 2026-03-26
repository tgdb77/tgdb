#!/bin/bash

# 系統管理：虛擬記憶體（Swap / 快取清理）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# 虛擬記憶體管理
manage_virtual_memory() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 虛擬記憶體管理 ❖"
        echo "=================================="
        
        echo "目前 Swap 狀態："
        free -h
        echo "----------------------------------"
        _virtual_memory_print_zram_status_inline
        echo "=================================="
        
        echo "可用操作："
        echo "1. 修改/創建 Swap 大小"
        echo "2. 清理記憶體快取"
        echo "3. 立即啟用 ZRAM（壓縮 Swap）"
        echo "4. 立即停用 ZRAM（壓縮 Swap）"
        echo "----------------------------------"
        echo "0. 返回系統管理選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-4]: " memory_choice
        
        case $memory_choice in
            1)
                modify_swap_size
                ;;
            2)
                clear_memory_cache
                ;;
            3)
                _virtual_memory_prompt_enable_zram_now
                ;;
            4)
                _virtual_memory_prompt_disable_zram_now
                ;;
            0)
                return
                ;;
            *)
                echo "無效選項"
                sleep 1
                ;;
        esac
    done
}

# 修改/創建 Swap 大小
virtual_memory_apply_swap_size() {
    local new_size="${1:-}"
    if [ -z "$new_size" ]; then
        new_size="1G"
    fi

    require_root || return 1

    if [ "$new_size" = "0" ]; then
        echo "正在刪除 Swap..."
        if [ -f /swapfile ]; then
            sudo swapoff /swapfile 2>/dev/null || true
            sudo rm -f /swapfile
            sudo sed -i '\|/swapfile|d' /etc/fstab
            echo "✅ Swap 已成功刪除並停用。"
        else
            echo "ℹ️  系統中沒有找到 /swapfile，無需操作。"
        fi
        return 0
    fi

    if [[ ! "$new_size" =~ ^[0-9]+[GMgm]$ ]]; then
        tgdb_fail "無效的大小格式，請使用如 4G 或 512M 的格式" 1 || true
        return 1
    fi

    echo ""
    echo "正在修改 Swap 大小為 $new_size ..."

    if [ -f /swapfile ]; then
        echo "步驟 1/4: 停用並刪除現有 Swap..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    else
        echo "步驟 1/4: 跳過（無現有 Swap 文件）"
    fi

    echo "步驟 2/4: 創建新 Swap 文件 ($new_size)..."
    if sudo fallocate -l "$new_size" /swapfile; then
        echo "✅ Swap 文件創建成功"
    else
        tgdb_warn "使用 fallocate 失敗，嘗試使用 dd..."
        local dd_count
        local unit=${new_size: -1}
        local size_val=${new_size%?}
        if [[ "$unit" =~ [Gg] ]]; then
            dd_count=$((size_val * 1024))
        else
            dd_count=$size_val
        fi

        if sudo dd if=/dev/zero of=/swapfile bs=1M count="$dd_count" status=progress; then
            echo "✅ Swap 文件創建成功"
        else
            tgdb_fail "Swap 文件創建失敗" 1 || true
            return 1
        fi
    fi

    echo "步驟 3/4: 設定 Swap 文件權限..."
    sudo chmod 600 /swapfile

    echo "步驟 4/4: 格式化並啟用 Swap..."
    if sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile; then
        echo "✅ Swap 設定完成"

        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
            echo "✅ 已添加到 /etc/fstab，開機時自動啟用"
        else
            sudo sed -i '\|/swapfile|d' /etc/fstab
            echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
            echo "✅ 已更新 /etc/fstab 中的 Swap 設置"
        fi

        echo ""
        echo "新的 Swap 狀態："
        free -h || true
        return 0
    fi

    tgdb_fail "Swap 啟用失敗" 1 || true
    return 1
}

modify_swap_size() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 修改/創建 Swap 大小 ❖"
        echo "=================================="
        
        echo "目前 Swap 狀態："
        free -h
        if [ -f /swapfile ]; then
            local file_size
            file_size=$(stat -c '%s' /swapfile 2>/dev/null || echo "")
            echo "Swap 文件: /swapfile ($file_size)"
        else
            echo "Swap 文件: 不存在"
        fi
        echo "----------------------------------"
        
        echo "請輸入新的 Swap 大小 (例如: 2G, 512M)。"
        echo "輸入 0 將會刪除並停用 Swap。"
        echo "直接按 Enter 使用預設大小 1G。"
        echo "=================================="
        read -r -e -p "請輸入大小 [0, 2G, 4G...]: " new_size
        
        if [ -z "$new_size" ]; then
            new_size="1G"
        fi

        if virtual_memory_apply_swap_size "$new_size"; then
            pause
            return 0
        fi

        pause
    done
}

# 清理記憶體快取
clear_memory_cache() {
    maybe_clear
    echo "=================================="
    echo "❖ 清理記憶體快取 ❖"
    echo "=================================="
    
    echo "清理前記憶體狀態："
    echo "----------------------------------"
    free -h
    
    echo ""
    tgdb_warn "警告：清理記憶體快取會將緩存在 RAM 中的數據清除，"
    echo "   這可能會暫時降低系統性能，因為系統需要從磁碟重新讀取數據。"
    echo ""
    if ! system_admin_confirm_yn "確定要清理所有記憶體快取嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消"
        pause
        return
    fi
    
    echo ""
    echo "正在清理所有快取..."
    sync
    if echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null; then
        echo "✅ 所有快取已清理"
    else
        tgdb_fail "清理失敗" 1 || true
    fi
    
    echo ""
    echo "清理後記憶體狀態："
    echo "----------------------------------"
    free -h
    
    pause
}

_virtual_memory_print_zram_status_inline() {
    echo "ZRAM 狀態："

    if ! command -v swapon >/dev/null 2>&1; then
        echo "❌ 無法檢查（找不到 swapon）"
        return 0
    fi

    local zram_devices
    zram_devices=$(_virtual_memory_zram_swap_devices | tr '\n' ' ' | sed 's/[[:space:]]\+$//')
    if [ -n "$zram_devices" ]; then
        echo "✅ 已啟用：$zram_devices"
    else
        echo "❌ 未啟用"
    fi

    if _virtual_memory_is_systemd_available; then
        local enabled
        enabled=$(systemctl is-enabled tgdb-zram.service 2>/dev/null || echo "未啟用/不存在")
        echo "開機自動啟用（systemd）：$enabled"
    else
        echo "開機自動啟用（systemd）：不支援（非 systemd）"
    fi
}

_virtual_memory_get_mem_total_mb() {
    awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0"
}

_virtual_memory_recommend_zram_size() {
    local mem_mb
    mem_mb=$(_virtual_memory_get_mem_total_mb)

    if [ -z "${mem_mb:-}" ] || [ "$mem_mb" -le 0 ] 2>/dev/null; then
        echo "1G"
        return 0
    fi

    if [ "$mem_mb" -le 1024 ]; then
        echo "512M"
    elif [ "$mem_mb" -le 2048 ]; then
        echo "1G"
    elif [ "$mem_mb" -le 4096 ]; then
        echo "2G"
    else
        echo "4G"
    fi
}

_virtual_memory_zram_swap_devices() {
    swapon --noheadings --show=NAME 2>/dev/null | awk '/^\/dev\/zram/ {print $1}'
}

_virtual_memory_has_zram_swap_enabled() {
    _virtual_memory_zram_swap_devices | grep -q '^/dev/zram' 2>/dev/null
}

_virtual_memory_is_systemd_available() {
    command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

_virtual_memory_ensure_zram_prereqs() {
    local -a missing=()

    command -v zramctl >/dev/null 2>&1 || missing+=("zramctl")
    command -v modprobe >/dev/null 2>&1 || missing+=("modprobe")
    command -v mkswap >/dev/null 2>&1 || missing+=("mkswap")
    command -v swapon >/dev/null 2>&1 || missing+=("swapon")

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    tgdb_warn "缺少 ZRAM 需要的指令：${missing[*]}"
    echo "建議安裝套件：util-linux、kmod"
    echo ""

    if ! system_admin_confirm_yn "要嘗試自動安裝必要套件嗎？(Y/n，預設 N，輸入 0 取消): " "N"; then
        return 1
    fi

    if ! declare -F install_package >/dev/null 2>&1; then
        tgdb_fail "找不到套件安裝函式 install_package，無法自動安裝。" 1 || true
        echo "請手動安裝 util-linux、kmod 後重試。"
        return 1
    fi

    echo "正在安裝 util-linux、kmod..."
    if install_package util-linux kmod; then
        echo "✅ 套件安裝完成"
        return 0
    fi

    tgdb_fail "自動安裝失敗，請手動安裝 util-linux、kmod 後重試。" 1 || true
    return 1
}

_virtual_memory_pick_zram_algorithm() {
    local sysfs="/sys/block/zram0/comp_algorithm"
    if [ -r "$sysfs" ]; then
        if grep -qw "lz4" "$sysfs" 2>/dev/null; then
            echo "lz4"
            return 0
        fi
        awk '{for (i=1; i<=NF; i++) {gsub(/[\[\]]/, "", $i); if ($i != "") {print $i; exit}}}' "$sysfs" 2>/dev/null && return 0
    fi
    echo "lz4"
}

_virtual_memory_validate_size() {
    local size="$1"
    [[ "$size" =~ ^[0-9]+[GMgm]$ ]]
}

_virtual_memory_zram_enable_now() {
    local size="$1"
    local algo="$2"

    if _virtual_memory_has_zram_swap_enabled; then
        echo "ℹ️  目前已偵測到 ZRAM Swap 正在使用，將不重複啟用。"
        return 0
    fi

    _virtual_memory_ensure_zram_prereqs || return 1

    echo "正在載入 zram 模組..."
    sudo modprobe zram num_devices=1 2>/dev/null || sudo modprobe zram 2>/dev/null || true

    local dev=""
    if [ -n "${algo:-}" ]; then
        dev=$(sudo zramctl --find --size "$size" --algorithm "$algo" 2>/dev/null || echo "")
    fi
    if [ -z "$dev" ]; then
        dev=$(sudo zramctl --find --size "$size" 2>/dev/null || echo "")
    fi
    if [ -z "$dev" ]; then
        tgdb_fail "建立 ZRAM 裝置失敗（zramctl --find）。" 1 || true
        return 1
    fi

    echo "正在格式化 $dev 為 Swap..."
    if ! sudo mkswap "$dev" >/dev/null 2>&1; then
        tgdb_fail "mkswap 失敗：$dev" 1 || true
        return 1
    fi

    echo "正在啟用 ZRAM Swap（優先序 100）..."
    if ! sudo swapon -p 100 "$dev" 2>/dev/null; then
        tgdb_fail "swapon 失敗：$dev" 1 || true
        return 1
    fi

    echo "✅ ZRAM Swap 已啟用：$dev"
    return 0
}

_virtual_memory_zram_disable_now() {
    local dev
    local found=0
    while read -r dev; do
        [ -n "$dev" ] || continue
        found=1
        echo "正在停用 $dev..."
        sudo swapoff "$dev" 2>/dev/null || true
        if sudo zramctl --reset "$dev" 2>/dev/null; then
            :
        else
            local base
            base=$(basename "$dev" 2>/dev/null || echo "")
            if [ -n "$base" ] && [ -w "/sys/block/$base/reset" ]; then
                echo 1 | sudo tee "/sys/block/$base/reset" >/dev/null 2>&1 || true
            fi
        fi
    done < <(_virtual_memory_zram_swap_devices)

    if [ "$found" -eq 0 ]; then
        echo "ℹ️  目前沒有啟用中的 ZRAM Swap。"
    else
        sudo modprobe -r zram 2>/dev/null || true
        echo "✅ ZRAM Swap 已停用。"
    fi
}

_virtual_memory_systemd_unit_path() {
    echo "/etc/systemd/system/tgdb-zram.service"
}

_virtual_memory_write_systemd_unit() {
    local size="$1"
    local algo="$2"
    local unit_path
    unit_path=$(_virtual_memory_systemd_unit_path)

    if ! _virtual_memory_validate_size "$size"; then
        tgdb_fail "ZRAM 大小格式不正確：$size" 1 || true
        return 1
    fi
    if [[ ! "$algo" =~ ^[A-Za-z0-9._-]+$ ]]; then
        algo="lz4"
    fi

    echo "正在寫入 systemd 服務：$unit_path"
    local unit_content
    unit_content=$(
        cat <<'EOF'
[Unit]
Description=TGDB ZRAM Swap
After=systemd-modules-load.service
Before=swap.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'set -e; modprobe zram num_devices=1 2>/dev/null || modprobe zram; DEV="$(zramctl --find --size __SIZE__ --algorithm __ALGO__ 2>/dev/null || zramctl --find --size __SIZE__)"; mkswap "$DEV" >/dev/null; swapon -p 100 "$DEV"'
ExecStop=/bin/sh -c 'set +e; for DEV in $(swapon --noheadings --show=NAME 2>/dev/null | grep "^/dev/zram"); do swapoff "$DEV" 2>/dev/null || true; zramctl --reset "$DEV" 2>/dev/null || true; done; modprobe -r zram 2>/dev/null || true'

[Install]
WantedBy=swap.target
EOF
    )
    unit_content=${unit_content//__SIZE__/$size}
    unit_content=${unit_content//__ALGO__/$algo}

    if ! printf '%s\n' "$unit_content" | sudo tee "$unit_path" >/dev/null; then
        tgdb_fail "寫入失敗：$unit_path" 1 || true
        return 1
    fi

    return 0
}

_virtual_memory_disable_zram_on_boot() {
    local unit_path
    unit_path=$(_virtual_memory_systemd_unit_path)

    if ! _virtual_memory_is_systemd_available; then
        return 0
    fi

    echo "正在停用並停止 tgdb-zram.service..."
    sudo systemctl disable --now tgdb-zram.service 2>/dev/null || true

    if [ -f "$unit_path" ]; then
        sudo rm -f "$unit_path"
        sudo systemctl daemon-reload 2>/dev/null || true
        echo "✅ 已移除：$unit_path"
    fi
    return 0
}

_virtual_memory_enable_zram_and_persist() {
    local size="$1"
    local algo="$2"

    _virtual_memory_zram_enable_now "$size" "$algo" || return 1

    if _virtual_memory_is_systemd_available; then
        _virtual_memory_write_systemd_unit "$size" "$algo" || return 1
        sudo systemctl daemon-reload 2>/dev/null || true
        if sudo systemctl enable tgdb-zram.service >/dev/null 2>&1; then
            echo "✅ 已設定開機自動啟用 ZRAM（tgdb-zram.service）"
        else
            tgdb_warn "無法設定開機自動啟用（tgdb-zram.service），請手動檢查：sudo systemctl enable tgdb-zram.service"
        fi
    fi

    return 0
}

_virtual_memory_prompt_enable_zram_now() {
    local size
    local recommended
    recommended=$(_virtual_memory_recommend_zram_size)

    echo "建議大小（依 RAM 推估）：$recommended"
    echo "直接按 Enter 使用建議值。"
    read -r -e -p "請輸入 ZRAM 大小（例如 512M, 1G, 2G）: " size
    if [ -z "$size" ]; then
        size="$recommended"
    fi
    if ! _virtual_memory_validate_size "$size"; then
        tgdb_err "無效的大小格式，請使用如 1G 或 512M 的格式"
        pause
        return 1
    fi

    local algo
    algo=$(_virtual_memory_pick_zram_algorithm)

    echo ""
    echo "即將啟用 ZRAM（壓縮 Swap）：大小 $size，演算法 $algo（若不支援會自動退回預設）"
    echo "提示：啟用後將同時設定為開機自動啟用（若系統為 systemd）。"
    if ! system_admin_confirm_yn "確認要繼續嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消"
        pause
        return 0
    fi

    echo ""
    if _virtual_memory_enable_zram_and_persist "$size" "$algo"; then
        echo ""
        echo "目前 Swap 狀態："
        free -h
    fi
    pause
}

_virtual_memory_prompt_disable_zram_now() {
    if ! system_admin_confirm_yn "確認要停用所有 ZRAM Swap 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消"
        pause
        return 0
    fi
    echo ""
    _virtual_memory_zram_disable_now
    _virtual_memory_disable_zram_on_boot || true
    pause
}
