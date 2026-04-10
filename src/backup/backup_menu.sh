#!/bin/bash

# 全系統備份：主選單與 CLI 入口
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_BACKUP_MENU_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_MENU_LOADED=1

backup_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 全系統備份管理 ❖"
        echo "=================================="
        echo "TGDB 目錄: $TGDB_DIR"
        echo "全備位置: $BACKUP_DIR（全備最多 $(_backup_full_max_count_get) 份 / 指定備份最多 $(_backup_select_max_count_get) 份）"
        echo "策略提示：全備會停全部 TGDB 服務；指定備份只停所選實例。"
        echo "新環境使用者名稱需一致，避免目錄錯誤"
        echo "----------------------------------"
        echo "1. 立即建立備份"
        echo "2. 還原最新備份"
        echo "3. 指定實例備份（可多選）"
        echo "4. 還原指定實例最新備份"
        echo "5. 自動備份設定（systemd .timer）"
        echo "6. 指定備份自動化（systemd .timer）"
        echo "7. Kopia 管理（熱備：DB dump → snapshot）"
        echo "8. 已備份管理"
        echo "----------------------------------"
        echo "0. 返回主選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-8]: " choice
        case "$choice" in
            1)
                # 先嘗試備份 Fail2ban 與 nftables 設定，供日後手動還原使用
                if [ -f "$SCRIPT_DIR/fail2ban_manager.sh" ]; then
                    # shellcheck source=/dev/null
                    source "$SCRIPT_DIR/fail2ban_manager.sh"
                    backup_fail2ban_local
                fi
                if [ -f "$SCRIPT_DIR/nftables.sh" ]; then
                    # shellcheck source=/dev/null
                    source "$SCRIPT_DIR/nftables.sh"
                    nftables_backup
                fi
                backup_create
                ui_pause
                ;;
            2) backup_restore_latest_interactive ;;
            3) backup_create_selected_interactive ;;
            4) backup_restore_selected_latest_interactive ;;
            5) backup_timer_menu ;;
            6) backup_select_timer_menu ;;
            7)
                if [ -f "$SCRIPT_DIR/advanced/kopia-p.sh" ]; then
                    # shellcheck source=/dev/null
                    source "$SCRIPT_DIR/advanced/kopia-p.sh"
                    kopia_p_menu || true
                else
                    tgdb_fail "找不到 Kopia 模組：$SCRIPT_DIR/advanced/kopia-p.sh" 1 || true
                    ui_pause
                fi
                ;;
            8) backup_archives_manage_menu ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

# --- CLI 入口：提供給 systemd .service 使用 ---

backup_cli_main() {
    local subcmd="${1:-}"
    case "$subcmd" in
        auto-backup)
            backup_create
            ;;
        *)
            tgdb_fail "用法: $0 [auto-backup]" 1 || return $?
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    backup_cli_main "$@" || exit $?
fi

