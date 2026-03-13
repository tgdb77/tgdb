#!/bin/bash

# 系統管理：Cron 任務（可依需求客製預設任務範本/白名單）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# Cron 任務管理
manage_cron() {
    local current_user
    current_user=$(whoami)
    while true; do
        clear
        echo "=================================="
        echo "❖ Cron 任務管理 (用戶: $current_user) ❖"
        echo "=================================="
        crontab -l 2>/dev/null | cat -n || echo "目前沒有設定 Cron 任務。"
        echo "=================================="
        
        echo "可用操作："
        echo "1. 新增 Cron 任務"
        echo "2. 刪除 Cron 任務"
        echo "3. 手動編輯任務"
        echo "----------------------------------"
        echo "0. 返回系統管理選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-3]: " cron_choice

        case $cron_choice in
            1)
                add_cron_job
                ;;
            2)
                delete_cron_job
                ;;
            3)
                edit_cron_file
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

# 新增 Cron 任務
add_cron_job() {
    maybe_clear
    echo "=================================="
    echo "❖ 新增 Cron 任務 ❖"
    echo "=================================="
    echo "請輸入完整的 Cron 任務行。"
    echo "格式: 分 時 日 月 週 命令"
    echo "範例: */5 * * * * /usr/bin/bash /home/user/script.sh"
    echo "----------------------------------"
    read -r -e -p "請輸入任務行: " new_job
    
    if [ -z "$new_job" ]; then
        echo "未輸入任何內容，操作取消。"
    else
        (crontab -l 2>/dev/null; echo "$new_job") | crontab -
        echo "✅ 任務已新增。"
    fi
    
    pause
}

# 刪除 Cron 任務
delete_cron_job() {
    maybe_clear
    echo "=================================="
    echo "❖ 刪除 Cron 任務 ❖"
    echo "=================================="
    
    if ! crontab -l 2>/dev/null | grep -qv '^[[:space:]]*$'; then
        echo "目前沒有可刪除的 Cron 任務。"
        pause
        return
    fi
    
    echo "目前的 Cron 任務："
    crontab -l | cat -n
    echo "----------------------------------"
    read -r -e -p "請輸入要刪除的任務編號 (輸入 0 取消): " job_number
    
    if [[ ! "$job_number" =~ ^[0-9]+$ ]]; then
        echo "無效輸入，請輸入數字。"
        sleep 1
        return
    fi
    
    if [ "$job_number" -eq 0 ]; then
        echo "操作已取消。"
    else
        crontab -l | sed "${job_number}d" | crontab -
        echo "✅ 任務 $job_number 已刪除。"
    fi
    
    pause
}

# 手動編輯 Crontab 文件
edit_cron_file() {
    maybe_clear
    if crontab -e; then
        echo "✅ Cron 任務已更新。"
    else
        tgdb_err "操作取消或編輯時發生錯誤。"
    fi
    
    pause
}
