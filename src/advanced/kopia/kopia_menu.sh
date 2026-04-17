#!/bin/bash

# Kopia 管理：主選單
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_MENU_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_MENU_LOADED=1

kopia_p_menu() {
  _kopia_require_interactive || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ Kopia 管理 ❖"
    echo "=================================="
    _kopia_print_status || true
    echo "----------------------------------"
    echo "1. 部署 Kopia（Quadlet）"
    echo "2. 遠端 Repository 設定（rclone）"
    echo "3. 產生/更新 .kopiaignore（固定排除數據庫目錄）"
    echo "4. 編輯 .kopiaignore"
    echo "5. 統一備份排程（systemd --user timer）"
    echo "6. 還原快照（覆蓋模式）"
    echo "----------------------------------"
    echo "d. 完全移除"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-6,d]: " choice

    local runner
    runner="$(_kopia_runner_script)"

    case "$choice" in
      1)
        kopia_p_deploy || true
        ;;
      2)
        kopia_p_setup_remote_repository || true
        ;;
      3)
        if [ -f "$runner" ]; then
          bash "$runner" generate-ignore || true
        else
          tgdb_fail "找不到腳本：$runner" 1 || true
        fi
        ui_pause "按任意鍵返回..."
        ;;
      4)
        kopia_p_edit_ignore_file || true
        ;;
      5)
        _kopia_timer_menu || true
        ;;
      6)
        if [ -f "$runner" ]; then
          bash "$runner" restore-overwrite || true
        else
          tgdb_fail "找不到腳本：$runner" 1 || true
        fi
        ui_pause "按任意鍵返回..."
        ;;
      d)
        kopia_p_full_remove || true
        ;;
      0)
        return 0
        ;;
      *)
        echo "無效選項，請重新輸入。"
        sleep 1
        ;;
    esac
  done
}
