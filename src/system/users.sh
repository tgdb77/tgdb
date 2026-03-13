#!/bin/bash

# 系統管理：用戶/密碼管理（可依需求客製選單/策略）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# 修改用戶密碼
change_user_password() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 修改用戶密碼 ❖"
        echo "=================================="
        
        local current_user
        current_user=$(whoami)
        echo "當前用戶: $current_user"
        echo ""
        
        echo "可用操作："
        echo "1. 修改當前用戶密碼 ($current_user)"
        echo "2. 修改其他用戶密碼"
        echo "3. 修改 root 密碼"
        echo "----------------------------------"
        echo "0. 返回系統管理選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-3]: " password_choice
        
        case $password_choice in
            1)
                change_current_user_password
                ;;
            2)
                change_other_user_password
                ;;
            3)
                change_root_password
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

# 修改當前用戶密碼
change_current_user_password() {
    maybe_clear
    echo "=================================="
    echo "❖ 修改當前用戶密碼 ❖"
    echo "=================================="
    
    local current_user
    current_user=$(whoami)
    echo "正在修改用戶 '$current_user' 的密碼"
    echo ""
    tgdb_warn "注意：密碼輸入時不會顯示字符"
    if passwd; then
        echo ""
        echo "✅ 密碼修改成功！"
    else
        echo ""
        tgdb_err "密碼修改失敗"
    fi
    
    pause
}

# 修改其他用戶密碼
change_other_user_password() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 修改其他用戶密碼 ❖"
        echo "=================================="
        
        echo "系統用戶列表："
        echo "----------------------------------"
        local users=()
        while IFS=: read -r user _ uid _; do
            if [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ]; then
                users+=("$user")
            fi
        done < <(getent passwd | sort -t: -k1,1)
        
        if [ ${#users[@]} -eq 0 ]; then
            echo "沒有找到普通用戶"
            pause
            return
        fi
        
        local i=1
        for user in "${users[@]}"; do
            echo "$i. $user"
            i=$((i+1))
        done
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        if ! ui_prompt_index user_choice "請選擇要修改密碼的用戶 [0-${#users[@]}]: " 1 "${#users[@]}" "" 0; then
            return
        fi
        
        if [ "$user_choice" -ge 1 ] && [ "$user_choice" -le "${#users[@]}" ]; then
            local selected_user=${users[$((user_choice-1))]}
            
            maybe_clear
            echo "=================================="
            echo "❖ 修改用戶 '$selected_user' 的密碼 ❖"
            echo "=================================="
            echo ""
            tgdb_warn "注意：需要管理員權限"
            tgdb_warn "注意：密碼輸入時不會顯示字符"
            echo ""
            
            if sudo passwd "$selected_user"; then
                echo ""
                echo "✅ 用戶 '$selected_user' 的密碼修改成功！"
            else
                echo ""
                tgdb_err "密碼修改失敗"
            fi
            
            pause
        fi
    done
}

# 修改 root 密碼
change_root_password() {
    maybe_clear
    echo "=================================="
    echo "❖ 修改 root 密碼 ❖"
    echo "=================================="
    echo ""
    tgdb_warn "警告：修改 root 密碼是高風險操作"
    tgdb_warn "請確保您記住新密碼，否則可能無法獲得管理員權限"
    echo ""
    if ! system_admin_confirm_yn "確定要修改 root 密碼嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消"
        pause
        return
    fi
    
    echo ""
    echo "正在修改 root 用戶密碼..."
    tgdb_warn "注意：密碼輸入時不會顯示字符"
    echo ""
    if sudo passwd root; then
        echo ""
        echo "✅ root 密碼修改成功！"
        tgdb_warn "請務必記住新密碼"
    else
        echo ""
        tgdb_err "root 密碼修改失敗"
    fi
    
    pause
}

# 用戶管理
manage_users() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 用戶管理 ❖"
        echo "=================================="
        echo "系統用戶（部分）："
        getent passwd | awk -F: '$3 < 1000 && $3 > 0 {printf "%-15s UID: %-6s\n", $1, $3}' | head -10 
        echo ""
        echo "----------------------------------"
        echo "目前系統普通用戶："
        getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {printf "%-15s UID: %-6s 主目錄: %s\n", $1, $3, $6}' | sort
        echo "----------------------------------"
        echo "當前登錄用戶："
        who
        echo "----------------------------------"
        echo ""
        echo "可用操作："
        echo "1. 創建新用戶"
        echo "2. 刪除用戶"
        echo "3. 修改用戶權限"
        echo "----------------------------------"
        echo "0. 返回系統管理選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-3]: " user_choice
        
        case $user_choice in
            1)
                create_new_user
                ;;
            2)
                delete_user
                ;;
            3)
                modify_user_permissions
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

create_new_user() {
    maybe_clear
    echo "=================================="
    echo "❖ 創建新用戶 ❖"
    echo "=================================="
    read -r -e -p "請輸入新用戶名: " new_username
    
    if [ -z "$new_username" ]; then
        tgdb_err "用戶名不能為空"
        pause
        return
    fi
    
    if id "$new_username" &>/dev/null; then
        tgdb_err "用戶 '$new_username' 已存在"
        pause
        return
    fi
    
    if [[ ! "$new_username" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        tgdb_err "用戶名格式無效"
        tgdb_warn "用戶名必須以小寫字母開頭，只能包含小寫字母、數字、底線和連字號"
        pause
        return
    fi
    
    echo ""
    echo "用戶創建選項："
    echo "1. 創建普通用戶"
    echo "2. 創建管理員用戶（sudo 權限）"
    echo "0. 取消"
    read -r -e -p "請選擇 [0-2]: " user_type
    
    case $user_type in
        1)
            if sudo useradd -m -s /bin/bash "$new_username"; then
                echo "✅ 用戶 '$new_username' 創建成功"
                echo ""
                echo "正在設定密碼..."
                if sudo passwd "$new_username"; then
                    echo "✅ 密碼設定成功"
                else
                    tgdb_err "密碼設定失敗"
                fi

                if ! ssh_is_password_auth_enabled; then
                    tgdb_warn "目前 SSH 已禁用密碼登入，將另外為此用戶設定 SSH 金鑰登入。"
                    add_user_ssh_key_login_for_user "$new_username"
                fi
            else
                tgdb_err "用戶創建失敗"
            fi
            ;;
        2)
            if sudo useradd -m -s /bin/bash "$new_username"; then
                local admin_group
                admin_group=$(get_admin_group)
                if getent group "$admin_group" >/dev/null 2>&1; then
                    sudo usermod -aG "$admin_group" "$new_username"
                fi
                echo "✅ 管理員用戶 '$new_username' 創建成功"
                echo ""
                echo "正在設定密碼..."
                if sudo passwd "$new_username"; then
                    echo "✅ 密碼設定成功"
                else
                    tgdb_err "密碼設定失敗"
                fi

                if ! ssh_is_password_auth_enabled; then
                    tgdb_warn "目前 SSH 已禁用密碼登入，將另外為此管理員用戶設定 SSH 金鑰登入。"
                    add_user_ssh_key_login_for_user "$new_username"
                fi
            else
                tgdb_err "用戶創建失敗"
            fi
            ;;
        0)
            echo "操作已取消"
            ;;
        *)
            echo "無效選項"
            ;;
    esac
    
    pause
}

# 刪除用戶
delete_user() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 刪除用戶 ❖"
        echo "=================================="
        
        local current_user
        current_user=$(whoami)
        local users=()
        while IFS=: read -r user _ uid _; do
            if [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] && [ "$user" != "$current_user" ] && [ "$user" != "root" ]; then
                users+=("$user")
            fi
        done < <(getent passwd | sort -t: -k1,1)
        
        if [ ${#users[@]} -eq 0 ]; then
            echo "沒有可刪除的用戶"
            pause
            return
        fi
        
        echo "可刪除的用戶："
        echo "----------------------------------"
        local i=1
        for user in "${users[@]}"; do
            echo "$i. $user"
            i=$((i+1))
        done
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        if ! ui_prompt_index user_choice "請選擇要刪除的用戶 [0-${#users[@]}]: " 1 "${#users[@]}" "" 0; then
            return
        fi
        
        if [ "$user_choice" -ge 1 ] && [ "$user_choice" -le "${#users[@]}" ]; then
            local selected_user=${users[$((user_choice-1))]}
            
            echo ""
            tgdb_warn "警告：即將刪除用戶 '$selected_user'"
            echo ""
            echo "刪除選項："
            echo "1. 只刪除用戶（保留主目錄）"
            echo "2. 刪除用戶和主目錄"
            echo "0. 取消"
            read -r -e -p "請選擇 [0-2]: " delete_option
            
            case $delete_option in
                1)
                    if sudo userdel "$selected_user"; then
                        echo "✅ 用戶 '$selected_user' 已刪除（主目錄已保留）"
                    else
                        tgdb_err "用戶刪除失敗"
                    fi
                    ;;
                2)
                    if system_admin_confirm_yn "確定要刪除用戶 '$selected_user' 和其主目錄嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
                        if sudo userdel -r "$selected_user"; then
                            echo "✅ 用戶 '$selected_user' 和主目錄已刪除"
                        else
                            tgdb_err "用戶刪除失敗"
                        fi
                    else
                        echo "操作已取消"
                    fi
                    ;;
                0)
                    echo "操作已取消"
                    ;;
                *)
                    echo "無效選項"
                    ;;
            esac
        fi
        
        pause
    done
}

# 修改用戶權限
modify_user_permissions() {
    while true; do
        maybe_clear
        echo "=================================="
        echo "❖ 修改用戶權限 ❖"
        echo "=================================="
        
        local current_user
        current_user=$(whoami)
        local users=()
        while IFS=: read -r user _ uid _; do
            if [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] && [ "$user" != "$current_user" ]; then
                users+=("$user")
            fi
        done < <(getent passwd | sort -t: -k1,1)
        
        if [ ${#users[@]} -eq 0 ]; then
            echo "沒有可修改權限的用戶"
            pause
            return
        fi
        
        echo "用戶列表："
        echo "----------------------------------"
        local i=1
        for user in "${users[@]}"; do
            local label="普通用戶"
            if id -nG "$user" | grep -qw "$(get_admin_group)"; then
                label="管理員"
            fi
            echo "$i. $user ($label)"
            i=$((i+1))
        done
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        if ! ui_prompt_index user_choice "請選擇要修改權限的用戶 [0-${#users[@]}]: " 1 "${#users[@]}" "" 0; then
            return
        fi
        
        if [ "$user_choice" -ge 1 ] && [ "$user_choice" -le "${#users[@]}" ]; then
            local selected_user=${users[$((user_choice-1))]}
            local admin_group
            admin_group=$(get_admin_group)
            
            local is_admin=false
            if id -nG "$selected_user" | grep -qw "$admin_group"; then
                is_admin=true
            fi
            
            echo ""
            echo "用戶 '$selected_user' 當前權限："
            if [ "$is_admin" = true ]; then
                echo "✅ 管理員權限 ($admin_group)"
            else
                echo "❌ 普通用戶權限"
            fi
            
            echo ""
            echo "權限操作："
            if [ "$is_admin" = true ]; then
                echo "1. 移除管理員權限"
            else
                echo "1. 授予管理員權限"
            fi
            echo "0. 返回"
            read -r -e -p "請選擇 [0-1]: " permission_choice
            
            case $permission_choice in
                1)
                    if [ "$is_admin" = true ]; then
                        if command -v deluser >/dev/null 2>&1; then
                            if sudo deluser "$selected_user" "$admin_group"; then
                                echo "✅ 已移除用戶 '$selected_user' 的管理員權限"
                            else
                                tgdb_err "權限修改失敗"
                            fi
                        else
                            if sudo gpasswd -d "$selected_user" "$admin_group"; then
                                echo "✅ 已移除用戶 '$selected_user' 的管理員權限"
                            else
                                tgdb_err "權限修改失敗"
                            fi
                        fi
                    else
                        if sudo usermod -aG "$admin_group" "$selected_user"; then
                            echo "✅ 已授予用戶 '$selected_user' 管理員權限"
                        else
                            tgdb_err "權限修改失敗"
                        fi
                    fi
                    ;;
                0)
                    return
                    ;;
                *)
                    echo "無效選項"
                    ;;
            esac
        else
            echo "無效選項"
            sleep 1
            continue
        fi
        
        pause
    done
}
