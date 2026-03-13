#!/bin/bash

# 系統管理：Linux 內核參數（sysctl / BBR）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

_kernel_ensure_sysctl_dir() {
    local dir="/etc/sysctl.d"
    if [ -d "$dir" ]; then
        return 0
    fi

    echo "正在建立 $dir..."
    if sudo mkdir -p "$dir"; then
        return 0
    fi

    tgdb_fail "無法建立 $dir。" 1 || true
    return 1
}

# 從 config/utils 集中載入並套用 TGDB 內核參數設定檔
apply_kernel_profile() {
    local profile_name="$1"
    local profile_file="$UTILS_CONFIG_DIR/configs/kernel_${profile_name}.conf"

    if [ ! -f "$profile_file" ]; then
        tgdb_fail "找不到內核參數設定檔：$profile_file" 1 || true
        tgdb_warn "請檢查 config/utils/configs 是否存在對應檔案。"
        return 1
    fi

    echo "使用設定檔：$profile_file"

    if ! _kernel_ensure_sysctl_dir; then
        return 1
    fi
    if ! sudo cp "$profile_file" /etc/sysctl.d/99-tgdb.conf; then
        tgdb_fail "無法寫入 /etc/sysctl.d/99-tgdb.conf" 1 || true
        return 1
    fi

    sudo sysctl --system >/dev/null 2>&1 || sudo sysctl -p /etc/sysctl.d/99-tgdb.conf >/dev/null 2>&1 || true

    return 0
}

# Linux 內核參數調整
manage_kernel_parameters() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ Linux 內核參數調整 ❖"
        echo "=================================="
        tgdb_warn "注意：將寫入 /etc/sysctl.d/99-tgdb.conf 以持久化；可用『還原預設值』移除"
        echo "----------------------------------"
        echo "調整模式："
        echo "1. 還原預設值"
        echo "2. 性能最大化模式"
        echo "3. 均衡性能模式"
        echo "4. 雲端硬碟特調模式"
        echo "5. 一鍵啟用 BBR+FQ 網路加速"
        echo "6. 查看目前參數狀態"
        echo "----------------------------------"
        echo "0. 返回系統管理選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-6]: " kernel_choice
        
        case $kernel_choice in
            1)
                restore_default_parameters
                ;;
            2)
                apply_performance_max_mode
                ;;
            3)
                apply_balanced_mode
                ;;
            4)
                apply_cloud_storage_mode
                ;;
            5)
                enable_bbr_fq
                ;;
            6)
                show_current_parameters
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

# 還原預設值
restore_default_parameters() {
    maybe_clear
    echo "=================================="
    echo "❖ 還原預設值 ❖"
    echo "=================================="
    echo "正在移除 TGDB 專用 sysctl 設定並重新載入..."
    if [ -f /etc/sysctl.d/99-tgdb.conf ]; then
        sudo rm -f /etc/sysctl.d/99-tgdb.conf
    fi
    sudo sysctl --system >/dev/null 2>&1 || sudo sysctl -p >/dev/null 2>&1 || true
    echo "✅ 內核參數已回復系統預設（或先前設定）。"
    pause
}

# 性能最大化模式
apply_performance_max_mode() {
    maybe_clear
    echo "=================================="
    echo "❖ 性能最大化模式 ❖"
    echo "=================================="
    echo "正在套用性能最大化參數..."
    
    echo "1/2: 優化檔案描述符限制..."
    grep -q "^\* soft nofile 65536$" /etc/security/limits.conf 2>/dev/null || echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf >/dev/null 2>&1
    grep -q "^\* hard nofile 65536$" /etc/security/limits.conf 2>/dev/null || echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf >/dev/null 2>&1
    ulimit -n 65536 2>/dev/null || true
    
    echo "2/2: 套用內核參數設定檔..."
    if apply_kernel_profile "performance_max"; then
        echo "✅ 性能最大化模式已套用（並已持久化）"
        echo "ℹ️  系統性能已優化，但資源消耗會增加"
    else
        tgdb_err "套用性能最大化模式失敗，請檢查設定檔。"
    fi
    
    pause
}

# 均衡性能模式
apply_balanced_mode() {
    maybe_clear
    echo "=================================="
    echo "❖ 均衡性能模式 ❖"
    echo "=================================="
    echo "正在套用均衡性能參數..."
    
    echo "1/2: 設定檔案描述符限制..."
    ulimit -n 32768 2>/dev/null || true
    
    echo "2/2: 套用內核參數設定檔..."
    if apply_kernel_profile "balanced"; then
        echo "✅ 均衡性能模式已套用（並已持久化）"
        echo "ℹ️  系統在效能與資源消耗間達到平衡"
    else
        tgdb_err "套用均衡性能模式失敗，請檢查設定檔。"
    fi
    
    pause
}

# 雲端硬碟特調模式
apply_cloud_storage_mode() {
    maybe_clear
    echo "=================================="
    echo "❖ 雲端硬碟特調模式 ❖"
    echo "=================================="
    echo "正在套用雲端硬碟特調參數..."
    
    echo "1/2: 優化檔案描述符限制..."
    ulimit -n 131072 2>/dev/null || true
    
    echo "2/2: 套用內核參數設定檔..."
    if apply_kernel_profile "cloud_storage"; then
        echo "✅ 雲端硬碟特調模式已套用（並已持久化）"
        echo "ℹ️  系統已針對檔案傳輸和雲端硬碟操作進行優化"
    else
        tgdb_err "套用雲端硬碟特調模式失敗，請檢查設定檔。"
    fi
    
    pause
}

# 啟用 BBR+FQ 網路加速
enable_bbr_fq() {
    maybe_clear
    echo "=================================="
    echo "❖ 啟用 BBR+FQ 網路加速 ❖"
    echo "=================================="
    local SYSCTL_CMD MODPROBE_CMD
    if [ "$(id -u)" -eq 0 ]; then
        SYSCTL_CMD=(sysctl)
        MODPROBE_CMD=(modprobe)
    else
        if ! command -v sudo >/dev/null 2>&1; then
            tgdb_fail "本操作需要 root 或 sudo 權限。請以 root 執行或安裝 sudo 後重試。" 1 || true
            pause
            return
        fi
        SYSCTL_CMD=(sudo sysctl)
        MODPROBE_CMD=(sudo modprobe)
    fi

    local avail_cc
    avail_cc=$("${SYSCTL_CMD[@]}" -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
    if [ -z "$avail_cc" ]; then
        tgdb_warn "無法讀取 net.ipv4.tcp_available_congestion_control。"
        tgdb_warn "請確認系統為 Linux，且可執行：sudo sysctl -n net.ipv4.tcp_available_congestion_control"
        pause
        return
    fi

    if ! echo "$avail_cc" | grep -qw "bbr"; then
        tgdb_warn "目前可用壅塞控制演算法：$avail_cc"
        echo "→ 嘗試載入 tcp_bbr 模組..."
        if "${MODPROBE_CMD[@]}" tcp_bbr 2>/dev/null; then
            avail_cc=$("${SYSCTL_CMD[@]}" -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
        fi
        if ! echo "$avail_cc" | grep -qw "bbr"; then
            tgdb_fail "仍未偵測到 bbr，可能是內核尚未啟用或版本過舊。" 1 || true
            tgdb_warn "請確認使用支援 BBR 的 Linux 內核，並已啟用 tcp_bbr 模組。"
            pause
            return
        fi
    fi

    local current_cc
    current_cc=$("${SYSCTL_CMD[@]}" -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    local current_qdisc
    current_qdisc=$("${SYSCTL_CMD[@]}" -n net.core.default_qdisc 2>/dev/null || echo "未知")

    echo "目前 TCP 壅塞控制: $current_cc"
    echo "目前預設佇列排程 (qdisc): $current_qdisc"
    echo "----------------------------------"
    echo "即將設定："
    echo "  net.core.default_qdisc = fq"
    echo "  net.ipv4.tcp_congestion_control = bbr"
    echo ""
    if ! system_admin_confirm_yn "確認要啟用 BBR+FQ 並寫入持久化設定嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消。"
        pause
        return
    fi

    local sysctl_file="/etc/sysctl.d/99-tgdb-bbr.conf"

    if ! _kernel_ensure_sysctl_dir; then
        pause
        return
    fi

    echo "正在寫入 $sysctl_file..."
    if ! printf "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n" | sudo tee "$sysctl_file" >/dev/null; then
        tgdb_fail "無法寫入 $sysctl_file。" 1 || true
        pause
        return
    fi

    echo "正在立即套用內核參數..."
    if ! "${SYSCTL_CMD[@]}" -p "$sysctl_file" >/dev/null 2>&1; then
        tgdb_warn "無法使用 sysctl -p 載入設定，改用 sysctl --system。"
        "${SYSCTL_CMD[@]}" --system >/dev/null 2>&1 || true
    fi

    current_cc=$("${SYSCTL_CMD[@]}" -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    current_qdisc=$("${SYSCTL_CMD[@]}" -n net.core.default_qdisc 2>/dev/null || echo "未知")

    echo ""
    echo "套用後狀態："
    echo "  TCP 壅塞控制: $current_cc"
    echo "  預設 qdisc : $current_qdisc"
    if [ "$current_cc" = "bbr" ] && [ "$current_qdisc" = "fq" ]; then
        echo "✅ BBR+FQ 已啟用並持久化。"
    else
        tgdb_warn "內核回報的設定與預期不完全一致，請手動檢查。"
    fi

    pause
}

enable_bbr_fq_cli() {
    echo "=================================="
    echo "❖ 啟用 BBR+FQ 網路加速（CLI）❖"
    echo "=================================="
    local SYSCTL_CMD MODPROBE_CMD
    if [ "$(id -u)" -eq 0 ]; then
        SYSCTL_CMD=(sysctl)
        MODPROBE_CMD=(modprobe)
    else
        if ! command -v sudo >/dev/null 2>&1; then
            tgdb_fail "本操作需要 root 或 sudo 權限。請以 root 執行或安裝 sudo 後重試。" 1 || true
            return 1
        fi
        SYSCTL_CMD=(sudo sysctl)
        MODPROBE_CMD=(sudo modprobe)
    fi

    local avail_cc
    avail_cc=$("${SYSCTL_CMD[@]}" -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
    if [ -z "$avail_cc" ]; then
        tgdb_fail "無法讀取 net.ipv4.tcp_available_congestion_control。" 1 || true
        return 1
    fi

    if ! echo "$avail_cc" | grep -qw "bbr"; then
        tgdb_warn "目前可用壅塞控制演算法：$avail_cc"
        echo "→ 嘗試載入 tcp_bbr 模組..."
        if "${MODPROBE_CMD[@]}" tcp_bbr 2>/dev/null; then
            avail_cc=$("${SYSCTL_CMD[@]}" -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
        fi
        if ! echo "$avail_cc" | grep -qw "bbr"; then
            tgdb_fail "仍未偵測到 bbr，可能是內核尚未啟用或版本過舊。" 1 || true
            tgdb_warn "請確認使用支援 BBR 的 Linux 內核，並已啟用 tcp_bbr 模組。"
            return 1
        fi
    fi

    local current_cc current_qdisc
    current_cc=$("${SYSCTL_CMD[@]}" -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    current_qdisc=$("${SYSCTL_CMD[@]}" -n net.core.default_qdisc 2>/dev/null || echo "未知")

    echo "目前 TCP 壅塞控制: $current_cc"
    echo "目前預設佇列排程 (qdisc): $current_qdisc"
    echo "----------------------------------"
    echo "即將設定："
    echo "  net.core.default_qdisc = fq"
    echo "  net.ipv4.tcp_congestion_control = bbr"

    local sysctl_file="/etc/sysctl.d/99-tgdb-bbr.conf"
    if ! _kernel_ensure_sysctl_dir; then
        return 1
    fi
    echo "正在寫入 $sysctl_file..."
    if ! printf "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n" | sudo tee "$sysctl_file" >/dev/null; then
        tgdb_fail "無法寫入 $sysctl_file。" 1 || true
        return 1
    fi

    echo "正在立即套用內核參數..."
    if ! "${SYSCTL_CMD[@]}" -p "$sysctl_file" >/dev/null 2>&1; then
        tgdb_warn "無法使用 sysctl -p 載入設定，改用 sysctl --system。"
        "${SYSCTL_CMD[@]}" --system >/dev/null 2>&1 || true
    fi

    current_cc=$("${SYSCTL_CMD[@]}" -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    current_qdisc=$("${SYSCTL_CMD[@]}" -n net.core.default_qdisc 2>/dev/null || echo "未知")

    echo ""
    echo "套用後狀態："
    echo "  TCP 壅塞控制: $current_cc"
    echo "  預設 qdisc : $current_qdisc"
    if [ "$current_cc" = "bbr" ] && [ "$current_qdisc" = "fq" ]; then
        echo "✅ BBR+FQ 已啟用並持久化。"
        return 0
    fi

    tgdb_warn "內核回報的設定與預期不完全一致，請手動檢查。"
    return 1
}

# 查看目前參數狀態
show_current_parameters() {
    maybe_clear
    echo "=================================="
    echo "❖ 目前內核參數狀態 ❖"
    echo "=================================="
    
    echo "網路參數："
    echo "----------------------------------"
    echo "TCP 接收緩衝區最大值: $(sudo sysctl -n net.core.rmem_max 2>/dev/null)"
    echo "TCP 發送緩衝區最大值: $(sudo sysctl -n net.core.wmem_max 2>/dev/null)"
    echo "網路設備佇列長度: $(sudo sysctl -n net.core.netdev_max_backlog 2>/dev/null)"
    echo "TCP 連接佇列長度: $(sudo sysctl -n net.core.somaxconn 2>/dev/null)"
    echo "TCP 壅塞控制演算法: $(sudo sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    
    echo ""
    echo "記憶體參數："
    echo "----------------------------------"
    echo "Swap 使用傾向: $(sudo sysctl -n vm.swappiness 2>/dev/null)"
    echo "髒頁比例: $(sudo sysctl -n vm.dirty_ratio 2>/dev/null)%"
    echo "背景寫入比例: $(sudo sysctl -n vm.dirty_background_ratio 2>/dev/null)%"
    echo "快取壓力: $(sudo sysctl -n vm.vfs_cache_pressure 2>/dev/null)"
    echo "最小可用記憶體: $(sudo sysctl -n vm.min_free_kbytes 2>/dev/null) KB"
    
    echo ""
    echo "檔案系統參數："
    echo "----------------------------------"
    echo "最大檔案描述符: $(sudo sysctl -n fs.file-max 2>/dev/null)"
    echo "目前檔案描述符限制: $(ulimit -n)"
    
    echo ""
    echo "系統狀態："
    echo "----------------------------------"
    echo "記憶體使用率: $(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
    echo "Swap 使用率: $(free | awk 'NR==3{if($2>0) printf "%.1f%%", $3*100/$2; else print "0.0%"}')"
    echo "TCP 連接數: $(sudo ss -t 2>/dev/null | wc -l)"
    if command -v lsof >/dev/null 2>&1; then
        echo "開啟的檔案數: $(sudo lsof 2>/dev/null | wc -l)"
    else
        echo "開啟的檔案數: $(awk '{print $1}' /proc/sys/fs/file-nr)"
    fi
    
    echo "=================================="
    pause
}
