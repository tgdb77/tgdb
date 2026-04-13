#!/bin/bash

# 第三方腳本管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

THIRD_PARTY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THIRD_PARTY_SUBSCRIPT_DIR="$THIRD_PARTY_SCRIPT_DIR/third_party"
# shellcheck source=src/core/bootstrap.sh disable=SC1091
[ -f "$THIRD_PARTY_SCRIPT_DIR/core/bootstrap.sh" ] && source "$THIRD_PARTY_SCRIPT_DIR/core/bootstrap.sh"

_third_party_source_script() {
  local script_name="$1"
  local path="$THIRD_PARTY_SUBSCRIPT_DIR/${script_name}.sh"

  if [ ! -f "$path" ]; then
    tgdb_fail "找不到第三方子腳本：$path" 1 || true
    return 1
  fi

  # shellcheck disable=SC1090 # 子腳本名稱由選單映射決定，於執行期載入
  source "$path"
}

_third_party_run_handler() {
  local script_name="$1"
  local handler="$2"

  _third_party_source_script "$script_name" || {
    ui_pause "載入第三方子腳本失敗，按任意鍵返回..." "main"
    return 1
  }

  if ! declare -F "$handler" >/dev/null 2>&1; then
    tgdb_fail "找不到第三方處理函式：$handler" 1 || true
    ui_pause "按任意鍵返回..." "main"
    return 1
  fi

  "$handler"
}

third_party_menu() {
  if ! ui_is_interactive; then
    tgdb_fail "第三方腳本管理需要互動式終端（TTY）。" 2 || return $?
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ 第三方腳本管理 ❖"
    echo "=================================="
    echo "提醒：以下腳本為第三方提供，請自行評估來源與風險。"
    echo "----------------------------------"
    echo "1. YABS 綜合測試 https://github.com/masonr/yet-another-bench-script"
    echo "2. VPS 系統重裝 https://github.com/bin456789/reinstall"
    echo "----------------------------------"
    echo "00. 自訂義指令"
    echo "----------------------------------"
    echo "0. 返回主選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-2,00]: " choice
    case "$choice" in
      1) _third_party_run_handler "yabs" "third_party_run_yabs" ;;
      2) _third_party_run_handler "reinstall" "third_party_run_reinstall" ;;
      00) third_party_run_rclone_custom_commands ;;
      0) return 0 ;;
      *) echo "無效選項"; sleep 1 ;;
    esac
  done
}

_third_party_load_module() {
  local module="$1"
  [ -n "$module" ] || return 0

  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "$module"
    return $?
  fi

  local path="$THIRD_PARTY_SCRIPT_DIR/${module}.sh"
  if [ ! -f "$path" ]; then
    path="$THIRD_PARTY_SCRIPT_DIR/advanced/${module}.sh"
  fi
  if [ ! -f "$path" ]; then
    tgdb_fail "找不到模組：$path" 1 || true
    return 1
  fi
  # shellcheck disable=SC1090 # 模組由參數決定，於執行期載入
  source "$path"
}

third_party_run_rclone_custom_commands() {
  _third_party_load_module "rclone" || {
    ui_pause "載入模組失敗，按任意鍵返回..." "main"
    return 1
  }

  if ! declare -F custom_commands_menu >/dev/null 2>&1; then
    tgdb_fail "找不到自訂義指令函式（custom_commands_menu）。" 1 || true
    ui_pause "按任意鍵返回..." "main"
    return 1
  fi

  custom_commands_menu
}
