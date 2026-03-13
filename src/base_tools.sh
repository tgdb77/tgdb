#!/bin/bash

# 基礎工具管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

BASE_TOOLS=(
  "curl"
  "wget"
  "sudo"
  "unzip"
  "tar"
  "ffmpeg"
  "btop"
  "nano"
  "git"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SCRIPT_DIR/core/bootstrap.sh"

_base_tools_collect_install_all() {
  local tool
  for tool in "${BASE_TOOLS[@]}"; do
    [ "$tool" = "ffmpeg" ] && continue
    check_tool_installed "$tool" || echo "$tool"
  done
}

_base_tools_collect_remove_all() {
  local tool
  for tool in "${BASE_TOOLS[@]}"; do
    [ "$tool" = "sudo" ] && continue
    check_tool_installed "$tool" && echo "$tool"
  done
}

_base_tools_install_tools() {
  local -a tools=("$@")
  [ ${#tools[@]} -gt 0 ] || return 0

  require_root || return 1
  echo "正在更新套件索引..."
  pkg_update || true

  local tool
  for tool in "${tools[@]}"; do
    echo "--- 安裝 $tool ---"
    install_single_tool "$tool" --no-update || return 1
  done
  return 0
}

_base_tools_remove_tools() {
  local -a tools=("$@")
  [ ${#tools[@]} -gt 0 ] || return 0

  require_root || return 1

  local tool
  for tool in "${tools[@]}"; do
    echo "--- 移除 $tool ---"
    remove_single_tool "$tool" --no-autoremove || return 1
  done

  echo "清理不需要的套件..."
  pkg_autoremove || true
  return 0
}

install_all_tools_cli() {
    echo "⚙️ (CLI) 安裝所有基礎工具（不含 ffmpeg）"

    local tools_to_install=()
    mapfile -t tools_to_install < <(_base_tools_collect_install_all)

    if [ ${#tools_to_install[@]} -eq 0 ]; then
        echo "🎉 除 ffmpeg 外，所有基礎工具都已安裝！"
        return 0
    fi

    echo "開始安裝基礎工具...（已略過 ffmpeg）"
    _base_tools_install_tools "${tools_to_install[@]}" || return 1

    echo "✅ 基礎工具安裝完成"
}

remove_all_tools_cli() {
    echo "⚙️ (CLI) 移除所有基礎工具（跳過 sudo）"

    local tools_to_remove=()
    mapfile -t tools_to_remove < <(_base_tools_collect_remove_all)
    _base_tools_remove_tools "${tools_to_remove[@]}" || return 1

    echo "✅ 基礎工具移除流程完成"
}

# 檢查工具是否已安裝
check_tool_installed() {
    local tool=$1
    if command -v "$tool" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 安裝單個工具
install_single_tool() {
    local tool=$1
    local no_update_flag="${2:-}"
    echo "正在安裝 $tool..."

    require_root || return 1

    if [ "$no_update_flag" = "--no-update" ]; then
        if ! pkg_install "$tool"; then
            tgdb_fail "$tool 安裝失敗" 1 || return $?
        fi
    elif ! install_package "$tool"; then
        tgdb_fail "$tool 安裝失敗" 1 || return $?
    fi

    if check_tool_installed "$tool"; then
        echo "✅ $tool 安裝成功"
    else
        tgdb_fail "安裝後未偵測到 $tool 可執行檔" 1 || return $?
    fi
}

# 移除單個工具
remove_single_tool() {
    local tool=$1
    local no_autoremove_flag="${2:-}"
    echo "正在移除 $tool..."

    if [ "$tool" = "sudo" ]; then
        tgdb_warn "警告：不建議移除 sudo，跳過"
        return
    fi

    require_root || return 1

    pkg_purge "$tool" || true
    if [ "$no_autoremove_flag" != "--no-autoremove" ]; then
        pkg_autoremove || true
    fi

    if ! check_tool_installed "$tool"; then
        echo "✅ $tool 移除成功"
    else
        tgdb_fail "$tool 移除失敗" 1 || return $?
    fi
}

# 顯示工具狀態
show_tools_status() {
    clear
    print_header "基礎工具狀態"
    
    for tool in "${BASE_TOOLS[@]}"; do
        if check_tool_installed "$tool"; then
            echo "✅ $tool - 已安裝"
        else
            echo "❌ $tool - 未安裝"
        fi
    done
    
    print_hr
}

# 安裝所有工具（排除 ffmpeg）
install_all_tools() {
    if ! ui_is_interactive; then
        tgdb_fail "基礎工具管理需要互動式終端（TTY）。" 2 || return $?
    fi

    clear
    echo "=================================="
    echo "❖ 安裝所有基礎工具 ❖"
    echo "=================================="
    echo "提示：本操作將安裝除 ffmpeg 以外的所有基礎工具"
    
    local tools_to_install=()
    local already_installed=()
    
    for tool in "${BASE_TOOLS[@]}"; do
        if [ "$tool" = "ffmpeg" ]; then
            continue
        fi
        if check_tool_installed "$tool"; then
            already_installed+=("$tool")
        else
            tools_to_install+=("$tool")
        fi
    done
    
    if [ ${#already_installed[@]} -gt 0 ]; then
        echo "已安裝的工具："
        for tool in "${already_installed[@]}"; do
            echo "✅ $tool"
        done
        echo ""
    fi
    
    if [ ${#tools_to_install[@]} -eq 0 ]; then
        echo "🎉 除 ffmpeg 外，所有基礎工具都已安裝！"
        ui_pause
        return
    fi
    
    echo "需要安裝的工具（不含 ffmpeg）："
    for tool in "${tools_to_install[@]}"; do
        echo "❌ $tool"
    done
    echo ""

    if ! ui_confirm_yn "確定要安裝這些工具嗎？(Y/n，預設 N，輸入 0 取消): " "N"; then
        echo "操作已取消"
        ui_pause
        return
    fi
    
    echo ""
    echo ""
    echo "開始安裝基礎工具...（已略過 ffmpeg）"
    echo ""
    _base_tools_install_tools "${tools_to_install[@]}" || { ui_pause; return 1; }
    
    echo ""
    echo "=================================="
    echo "✅ 基礎工具安裝完成"
    echo "=================================="
    ui_pause
}

# 移除所有工具
remove_all_tools() {
    if ! ui_is_interactive; then
        tgdb_fail "基礎工具管理需要互動式終端（TTY）。" 2 || return $?
    fi

    clear
    echo "=================================="
    echo "❖ 移除所有基礎工具 ❖"
    echo "=================================="
    tgdb_warn "警告：這將移除所有基礎工具（除了 sudo）"
    echo ""

    if ui_confirm_yn "確定要繼續嗎？(Y/n，預設 N，輸入 0 取消): " "N"; then
        echo ""
        echo "開始移除基礎工具..."

        local tools_to_remove=()
        mapfile -t tools_to_remove < <(_base_tools_collect_remove_all)
        _base_tools_remove_tools "${tools_to_remove[@]}" || { ui_pause; return 1; }
        
        echo ""
        echo "=================================="
        echo "✅ 基礎工具移除完成"
        echo "=================================="
    else
        echo "操作已取消"
    fi
    
    ui_pause
}

# 多選安裝工具
multi_select_install() {
    if ! ui_is_interactive; then
        tgdb_fail "基礎工具管理需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 多選安裝工具 ❖"
        echo "=================================="
        
        local i=1
        for tool in "${BASE_TOOLS[@]}"; do
            if check_tool_installed "$tool"; then
                echo "$i. $tool - 已安裝 ✅"
            else
                echo "$i. $tool - 未安裝 ❌"
            fi
            ((i++))
        done
        
        echo "----------------------------------"
        echo "輸入格式："
        echo "• 單個工具：1"
        echo "• 多個工具：1 3 5"
        echo "• 範圍選擇：1-5"
        echo "• 混合選擇：1 3-5 7"
        echo "----------------------------------"
        echo "0. 返回上級選單"
        echo "=================================="
        read -r -e -p "請輸入要安裝的工具編號: " input
        
        if [ "$input" = "0" ]; then
            break
        fi
        
        local selected_numbers=()
        parse_selection "$input" selected_numbers
        
        if [ ${#selected_numbers[@]} -eq 0 ]; then
            tgdb_err "無效輸入"
            sleep 1
            continue
        fi
        
        local selected_tools=()
        local tools_to_install=()
        
        for num in "${selected_numbers[@]}"; do
            if [ "$num" -ge 1 ] && [ "$num" -le "${#BASE_TOOLS[@]}" ]; then
                local tool="${BASE_TOOLS[$((num-1))]}"
                selected_tools+=("$tool")
                if ! check_tool_installed "$tool"; then
                    tools_to_install+=("$tool")
                fi
            fi
        done
        
        if [ ${#selected_tools[@]} -eq 0 ]; then
            tgdb_err "沒有選擇有效的工具"
            sleep 1
            continue
        fi
        
        echo ""
        echo "已選擇的工具："
        for tool in "${selected_tools[@]}"; do
            if check_tool_installed "$tool"; then
                echo "✅ $tool - 已安裝"
            else
                echo "❌ $tool - 未安裝"
            fi
        done
        
        if [ ${#tools_to_install[@]} -eq 0 ]; then
            echo ""
            echo "🎉 所選工具都已安裝！"
            ui_pause "按任意鍵繼續..."
            continue
        fi
        
        echo ""
        if ui_confirm_yn "確定要安裝這些工具嗎？(Y/n，預設 N，輸入 0 取消): " "N"; then
            echo ""
            _base_tools_install_tools "${tools_to_install[@]}" || { ui_pause "按任意鍵繼續..."; continue; }
            
            echo "✅ 安裝完成"
        else
            echo "操作已取消"
        fi
        
        ui_pause "按任意鍵繼續..."
    done
}

# 多選移除工具
multi_select_remove() {
    if ! ui_is_interactive; then
        tgdb_fail "基礎工具管理需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 多選移除工具 ❖"
        echo "=================================="
        
        local i=1
        for tool in "${BASE_TOOLS[@]}"; do
            if check_tool_installed "$tool"; then
                echo "$i. $tool - 已安裝 ✅"
            else
                echo "$i. $tool - 未安裝 ❌"
            fi
            ((i++))
        done
        
        echo "----------------------------------"
        echo "輸入格式："
        echo "• 單個工具：1"
        echo "• 多個工具：1 3 5"
        echo "• 範圍選擇：1-5"
        echo "• 混合選擇：1 3-5 7"
        echo "----------------------------------"
        echo "0. 返回上級選單"
        echo "=================================="
        read -r -e -p "請輸入要移除的工具編號: " input
        
        if [ "$input" = "0" ]; then
            break
        fi
        
        local selected_numbers=()
        parse_selection "$input" selected_numbers
        
        if [ ${#selected_numbers[@]} -eq 0 ]; then
            tgdb_err "無效輸入"
            sleep 1
            continue
        fi
        
        local selected_tools=()
        local tools_to_remove=()
        
        for num in "${selected_numbers[@]}"; do
            if [ "$num" -ge 1 ] && [ "$num" -le "${#BASE_TOOLS[@]}" ]; then
                local tool="${BASE_TOOLS[$((num-1))]}"
                selected_tools+=("$tool")
                if check_tool_installed "$tool" && [ "$tool" != "sudo" ]; then
                    tools_to_remove+=("$tool")
                fi
            fi
        done
        
        if [ ${#selected_tools[@]} -eq 0 ]; then
            tgdb_err "沒有選擇有效的工具"
            sleep 1
            continue
        fi
        
        echo ""
        echo "已選擇的工具："
        for tool in "${selected_tools[@]}"; do
            if [ "$tool" = "sudo" ]; then
                echo "⚠️  $tool - 不建議移除，將跳過"
            elif check_tool_installed "$tool"; then
                echo "✅ $tool - 已安裝"
            else
                echo "❌ $tool - 未安裝"
            fi
        done
        
        if [ ${#tools_to_remove[@]} -eq 0 ]; then
            echo ""
            echo "🎉 沒有可移除的工具！"
            ui_pause "按任意鍵繼續..."
            continue
        fi
        
        echo ""
        tgdb_warn "警告：這將移除選中的工具"
        if ui_confirm_yn "確定要移除這些工具嗎？(Y/n，預設 N，輸入 0 取消): " "N"; then
            echo ""
            _base_tools_remove_tools "${tools_to_remove[@]}" || { ui_pause "按任意鍵繼續..."; continue; }
            
            echo "✅ 移除完成"
        else
            echo "操作已取消"
        fi
        
        ui_pause "按任意鍵繼續..."
    done
}

# 解析選擇輸入（支持範圍和多選）
parse_selection() {
    local input="$1"
    local -n result_array=$2
    result_array=()
    
    local -a parts
    read -r -a parts <<< "$input"
    
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^[0-9]+$ ]]; then
            result_array+=("$part")
        elif [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
            local start
            start=$(echo "$part" | cut -d'-' -f1)
            local end
            end=$(echo "$part" | cut -d'-' -f2)
            
            if [ "$start" -le "$end" ]; then
                for ((i=start; i<=end; i++)); do
                    result_array+=("$i")
                done
            fi
        fi
    done
    
    local -a unique_array
    mapfile -t unique_array < <(printf '%s\n' "${result_array[@]}" | awk 'NF' | sort -nu)
    result_array=("${unique_array[@]}")
}

# 基礎工具主選單
base_tools_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "基礎工具管理需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        show_tools_status
        echo ""
        echo "可用操作："
        echo "1. 安裝所有（不含 ffmpeg）"
        echo "2. 移除所有工具"
        echo "3. 多選安裝工具"
        echo "4. 多選移除工具"
        echo "----------------------------------"
        echo "0. 返回主選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-4]: " base_tools_choice
        
        case $base_tools_choice in
            1)
                install_all_tools
                ;;
            2)
                remove_all_tools
                ;;
            3)
                multi_select_install
                ;;
            4)
                multi_select_remove
                ;;
            0)
                break
                ;;
            *)
                echo "無效選項，請重新輸入。"
                sleep 1
                ;;
        esac
    done
}
