#!/bin/bash

# 第三方腳本管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

THIRD_PARTY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/core/bootstrap.sh
[ -f "$THIRD_PARTY_SCRIPT_DIR/core/bootstrap.sh" ] && source "$THIRD_PARTY_SCRIPT_DIR/core/bootstrap.sh"

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
    echo "----------------------------------"
    echo "00. 自訂義指令"
    echo "----------------------------------"
    echo "0. 返回主選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-1,00]: " choice
    case "$choice" in
      1) third_party_run_yabs ;;
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

third_party_run_yabs() {
  clear || true
  echo "=================================="
  echo "❖ YABS 綜合測試 ❖"
  echo "=================================="
  echo "即將執行：curl -sL https://yabs.sh | bash"
  echo ""

  if ! command -v curl >/dev/null 2>&1; then
    tgdb_fail "系統未安裝 curl，無法執行 YABS。請先到「基礎工具管理」安裝 curl。" 1 || true
    ui_pause "按任意鍵返回..." "main"
    return 1
  fi

  local rc=0
  ( set +e; set +o pipefail; curl -sL https://yabs.sh | bash -s -- -r -5) || rc=$?
  echo ""

  if [ "$rc" -eq 0 ]; then
    echo "✅ YABS 執行完成"
  else
    tgdb_warn "YABS 執行結束（返回碼：$rc），請自行檢查輸出是否完整。"
  fi

  ui_pause "執行完成，按任意鍵繼續..." "main"
  return 0
}
