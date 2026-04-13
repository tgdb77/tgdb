#!/bin/bash

# 系統管理：主機名稱
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# 修改主機名稱
change_hostname() {
    maybe_clear
    echo "=================================="
    echo "❖ 修改主機名稱 ❖"
    echo "=================================="
    
    local current_hostname
    current_hostname=$(hostname)
    echo "目前主機名稱: $current_hostname"
    echo "----------------------------------"
    
    echo "請輸入新的主機名稱 (例如: my-server)。"
    echo "主機名稱只能包含小寫字母、數字和連字號 (-)。"
    echo "直接按 Enter 返回。"
    echo "=================================="
    read -r -e -p "請輸入新的主機名稱: " new_hostname
    
    if [ -z "$new_hostname" ]; then
        return
    fi
    
    if [[ ! "$new_hostname" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        echo ""
        tgdb_err "無效的主機名稱格式。"
        echo "   必須以小寫字母或數字開頭和結尾，中間只能包含小寫字母、數字和連字號。"
        pause
        return
    fi
    
    if [ "$new_hostname" == "$current_hostname" ]; then
        echo ""
        echo "ℹ️  新的主機名稱與目前名稱相同，無需變更。"
        pause
        return
    fi
      
    echo ""
    if ! system_admin_confirm_yn "確定要將主機名稱從 '$current_hostname' 變更為 '$new_hostname' 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消"
        pause
        return
    fi
    
    echo ""
    echo "正在變更主機名稱..."
    
    if sudo hostnamectl set-hostname "$new_hostname"; then
        echo "✅ 主機名稱已成功變更為 '$new_hostname'。"
        
        if [ -f /etc/hosts ]; then
            local hosts_tmp
            hosts_tmp=$(mktemp)

            if [ -n "$hosts_tmp" ] && awk -v current_hostname="$current_hostname" -v new_hostname="$new_hostname" '
                BEGIN {
                    updated = 0
                }
                /^127\.0\.0\.1([[:space:]]|$)/ && !updated {
                    delete seen
                    delete aliases
                    alias_count = 0
                    has_new = 0

                    for (i = 2; i <= NF; i++) {
                        alias = $i

                        if (alias == current_hostname) {
                            alias = new_hostname
                        }

                        if (alias == new_hostname) {
                            has_new = 1
                        }

                        if (!(alias in seen)) {
                            seen[alias] = 1
                            aliases[++alias_count] = alias
                        }
                    }

                    printf "127.0.0.1"
                    for (i = 1; i <= alias_count; i++) {
                        printf "\t%s", aliases[i]
                    }

                    if (!has_new && !(new_hostname in seen)) {
                        printf "\t%s", new_hostname
                    }

                    printf "\n"
                    updated = 1
                    next
                }
                {
                    print
                }
                END {
                    if (!updated) {
                        printf "127.0.0.1\t%s\n", new_hostname
                    }
                }
            ' /etc/hosts > "$hosts_tmp" && sudo cp "$hosts_tmp" /etc/hosts; then
                if grep -qE "^127\\.0\\.0\\.1\\b.*(^|[[:space:]])${new_hostname}([[:space:]]|$)" /etc/hosts; then
                    echo "✅ /etc/hosts 文件已更新。"
                else
                    tgdb_warn "已嘗試更新 /etc/hosts，但未確認到 127.0.0.1 主機名對應，請手動檢查。"
                fi
            else
                tgdb_warn "更新 /etc/hosts 文件失敗，可能需要手動檢查。"
            fi

            [ -n "$hosts_tmp" ] && rm -f "$hosts_tmp"
        fi
        
        echo ""
        echo "ℹ️  為了讓所有服務完全套用新的主機名稱，建議重新啟動系統。"
    else
        tgdb_fail "主機名稱變更失敗。" 1 || true
    fi
    
    pause
}
