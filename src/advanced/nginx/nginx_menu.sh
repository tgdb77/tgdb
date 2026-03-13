#!/bin/bash

# Nginx：互動選單
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_NGINX_MENU_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_MENU_LOADED=1

NGINX_MENU_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/advanced/nginx/nginx_waf.sh
source "$NGINX_MENU_SCRIPT_DIR/nginx_waf.sh"
# shellcheck source=src/advanced/nginx/nginx_sites.sh
source "$NGINX_MENU_SCRIPT_DIR/nginx_sites.sh"
# shellcheck source=src/advanced/nginx/nginx_quadlet.sh
source "$NGINX_MENU_SCRIPT_DIR/nginx_quadlet.sh"
# shellcheck source=src/advanced/nginx/nginx_logs.sh
source "$NGINX_MENU_SCRIPT_DIR/nginx_logs.sh"
# shellcheck source=src/advanced/nginx/nginx_timers.sh
source "$NGINX_MENU_SCRIPT_DIR/nginx_timers.sh"
# shellcheck source=src/advanced/nginx/nginx_certs.sh
source "$NGINX_MENU_SCRIPT_DIR/nginx_certs.sh"

# --- 選單 ---
nginx_p_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "Nginx 管理需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        _nginx_kill_stale_log_tails_on_tty
        clear
        echo "=================================="
        echo "❖ Nginx 管理❖"
        echo "教學與文件：https://nginx.org/en/docs/"
        echo "=================================="
        _nginx_print_sites_cert_summary 0
        echo "----------------------------------"
        echo "1. 部署/初始化"
        echo "2. 更新"
        echo "3. 新增反向代理站"
        echo "4. 新增靜態站"
        echo "5. 更新指定網站憑證"
        echo "6. 清除站點快取"
        echo "7. 編輯 nginx.conf"
        echo "8. 編輯指定站點 conf"
        echo "9. 刪除站點"
        echo "10. 新增/匯入自備憑證（crt/key）"
        echo "11. 追蹤日誌"
        echo "12. 自動任務設定（SSL/CF/WAF）"
        echo "13. WAF（ModSecurity + OWASP CRS）"
        echo "----------------------------------"
        echo "d. 完全移除"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-13/d]: " choice
        case "$choice" in
            1) nginx_p_deploy || true ;;
            2) nginx_p_update || true ;;
            3) nginx_p_add_reverse_proxy_site || true ;;
            4) nginx_p_add_static_site || true ;;
            5) nginx_p_update_cert_for_site || true ;;
            6) nginx_p_clear_site_cache || true ;;
            7) nginx_p_edit_main_conf || true ;;
            8) nginx_p_edit_site_conf || true ;;
            9) nginx_p_delete_site || true ;;
            10) nginx_p_add_custom_cert || true ;;
            11) nginx_p_tail_journal || true ;;
            12) nginx_p_timers_menu || true ;;
            13) nginx_p_waf_menu || true ;;
            d) nginx_p_remove || true ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}
