#!/bin/bash

# 系統管理：時區
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# 調整系統時區
timezone_apply() {
    local new_timezone="${1:-}"
    if [ -z "$new_timezone" ]; then
        tgdb_fail "時區不可為空" 1 || true
        return 1
    fi

    if ! command -v timedatectl >/dev/null 2>&1; then
        tgdb_fail "找不到 timedatectl，無法設定時區。" 1 || true
        return 1
    fi

    if ! timedatectl list-timezones 2>/dev/null | grep -q "^$new_timezone$"; then
        tgdb_fail "時區 '$new_timezone' 不存在或格式錯誤。" 1 || true
        return 1
    fi

    echo "正在設定時區為：$new_timezone ..."
    if sudo timedatectl set-timezone "$new_timezone"; then
        echo "✅ 時區已成功設定為 '$new_timezone'。"
        return 0
    fi

    tgdb_fail "時區設定失敗。" 1 || true
    return 1
}

manage_timezone() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 系統時區調整 ❖"
        echo "=================================="
        
        local current_timezone
        current_timezone=$(timedatectl | awk -F': ' '/Time zone/{print $2}' | awk '{print $1}')
        echo "目前系統時區: $current_timezone"
        echo "----------------------------------"
        
        echo "常用時區選項："
        echo "1. Asia/Taipei (亞洲台北)"
        echo "2. America/New_York (美洲紐約)"
        echo "3. America/Los_Angeles (美洲洛杉磯)"
        echo "4. Europe/Amsterdam (歐洲阿姆斯特丹)"
        echo "5. Europe/London (歐洲倫敦)"
        echo "6. UTC (協調世界時)"
        echo "7. 手動輸入其他時區"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請選擇 [0-7]: " tz_choice
        
        local new_timezone=""
        case $tz_choice in
            1) new_timezone="Asia/Taipei" ;;
            2) new_timezone="America/New_York" ;;
            3) new_timezone="America/Los_Angeles" ;;
            4) new_timezone="Europe/Amsterdam" ;;
            5) new_timezone="Europe/London" ;;
            6) new_timezone="UTC" ;;
            7)
                echo ""
                echo "您可以從 'timedatectl list-timezones' 獲取完整列表。"
                read -r -e -p "請輸入完整的時區名稱: " custom_timezone
                if [ -z "$custom_timezone" ]; then
                    echo "未輸入時區，操作取消。"
                    pause
                    continue
                fi
                new_timezone="$custom_timezone"
                ;;
            0)
                return
                ;;
            *)
                echo "無效選項"
                sleep 1
                continue
                ;;
        esac
        
        if ! timedatectl list-timezones | grep -q "^$new_timezone$"; then
            echo ""
            tgdb_err "時區 '$new_timezone' 不存在或格式錯誤。"
            pause
            continue
        fi
        
        echo ""
        if timezone_apply "$new_timezone"; then
            echo ""
            echo "更新後的時間資訊："
            timedatectl
        fi
        pause
    done
}
