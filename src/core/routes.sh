#!/bin/bash

# TGDB 路由/註冊表（供互動選單與 CLI 共用）
# 目的：避免互動選單（tgdb.sh）與 CLI（src/core/cli.sh）各維護一份路由而分岔。
# 注意：此檔案為 library，請勿在此更改 shell options（例如 set -e）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_CORE_ROUTES_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_ROUTES_LOADED=1

# 統一的「請求退出」返回碼：由入口（tgdb.sh）負責轉換為真正的結束與提示。
# shellcheck disable=SC2034 # 供入口與其他模組引用
TGDB_RC_EXIT="${TGDB_RC_EXIT:-100}"

# 模組快取：避免在每次選單選擇時重複 source 同一個模組。
# 注意：routes.sh 可能在函式內被 source（例如 tgdb.sh:load_modules），
# 因此若要跨函式生命週期保留快取，需使用 declare -gA（Bash 4.2+）。
_tgdb_module_cache_support_assoc() {
  ( declare -gA __tgdb_cache_test=() ) >/dev/null 2>&1
}

tgdb_reset_module_cache() {
  if _tgdb_module_cache_support_assoc; then
    unset TGDB_LOADED_MODULES 2>/dev/null || true
    declare -gA TGDB_LOADED_MODULES=()
  fi
  TGDB_LOADED_MODULES_LIST=""
}

tgdb_load_module() {
  local module="$1"
  [ -z "$module" ] && return 0
  local force="${2:-}"

  local base="${SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local path="$base/${module}.sh"
  if [ ! -f "$path" ]; then
    local alt="$base/advanced/${module}.sh"
    if [ -f "$alt" ]; then
      path="$alt"
    else
    if declare -F tgdb_fail >/dev/null 2>&1; then
      tgdb_fail "找不到模組：$path（或 $alt）" 1 || true
    elif declare -F tgdb_set_last_error >/dev/null 2>&1; then
      tgdb_set_last_error "找不到模組：$path（或 $alt）" 1
    else
      # shellcheck disable=SC2034 # 供其他模組讀取（最後錯誤訊息/代碼）
      TGDB_LAST_ERROR_MSG="找不到模組：$path（或 $alt）"
      # shellcheck disable=SC2034 # 供其他模組讀取（最後錯誤訊息/代碼）
      TGDB_LAST_ERROR_CODE=1
    fi
    return 1
    fi
  fi

  # 允許外部在必要時強制重載（例如：更新後想載入新版本模組）
  if [ "$force" != "--force" ]; then
    if _tgdb_module_cache_support_assoc; then
      if ! declare -p TGDB_LOADED_MODULES >/dev/null 2>&1; then
        declare -gA TGDB_LOADED_MODULES=()
      fi
      if [ "${TGDB_LOADED_MODULES[$module]:-}" = "1" ]; then
        return 0
      fi
    else
      TGDB_LOADED_MODULES_LIST="${TGDB_LOADED_MODULES_LIST:-}"
      case " $TGDB_LOADED_MODULES_LIST " in
        *" $module "*) return 0 ;;
      esac
    fi
  fi

  # 若剛完成「更新/強制重載」，需要在載入模組時一併強制重載其依賴 library，
  # 否則模組本身的載入守衛（_TGDB_*_LOADED）會讓舊版函式定義留在同一個 shell 進程中。
  local need_force_lib_reload=0
  if [ "$force" = "--force" ] || [ "${TGDB_FORCE_RELOAD_MODULES:-0}" = "1" ]; then
    need_force_lib_reload=1
  fi
  local old_force_set=0
  local old_force="${TGDB_FORCE_RELOAD_LIBS:-0}"
  if [ "${TGDB_FORCE_RELOAD_LIBS+x}" = "x" ]; then
    old_force_set=1
    old_force="$TGDB_FORCE_RELOAD_LIBS"
  fi
  if [ "$need_force_lib_reload" -eq 1 ]; then
    export TGDB_FORCE_RELOAD_LIBS=1
  fi

  # shellcheck disable=SC1090 # 模組由參數決定，於執行期載入
  source "$path"

  if [ "$need_force_lib_reload" -eq 1 ]; then
    if [ "$old_force_set" -eq 1 ]; then
      export TGDB_FORCE_RELOAD_LIBS="$old_force"
    else
      unset TGDB_FORCE_RELOAD_LIBS 2>/dev/null || true
    fi
  fi

  if _tgdb_module_cache_support_assoc; then
    TGDB_LOADED_MODULES["$module"]=1
  else
    TGDB_LOADED_MODULES_LIST="${TGDB_LOADED_MODULES_LIST:-}"
    TGDB_LOADED_MODULES_LIST="${TGDB_LOADED_MODULES_LIST}${TGDB_LOADED_MODULES_LIST:+ }$module"
  fi
}

tgdb_exit() {
  return "$TGDB_RC_EXIT"
}

# ---- 互動主選單路由（單一來源）----
# 格式: "code|label|module|function"
# - code：使用者輸入（字串比對，例如 00 / 777）
# - module：需載入的模組（none 表示不需載入）
# - function：要呼叫的函式（需已載入或在 module 中）
TGDB_MAIN_MENU_ROUTES=(
  "1|系統資訊|none|show_system_info"
  "2|系統維護|none|system_maintenance"
  "3|系統管理|system_admin|system_admin_menu"
  "4|基礎工具管理|base_tools|base_tools_menu"
  "5|Podman 管理|podman|podman_menu"
  "6|應用程式管理|apps-p|apps_p_menu"
  "7|進階應用|advanced_apps|advanced_apps_menu"
  "8|第三方腳本|third_party|third_party_menu"
  "9|快捷鍵管理|none|manage_shortcuts"
  "10|全系統備份管理|backup|backup_menu"
  "11|定時任務管理|timer|tgdb_timer_menu"
  "_sep_|----------------------------------||"
  "777|快速環境設定|none|env_setup_menu"
  "00|更新系統|none|update_tgdb"
  "_sep_|----------------------------------||"
  "0|退出|none|tgdb_exit"
)

tgdb_reserved_feature() {
  echo "=================================="
  echo "❖（保留功能）❖"
  echo "=================================="
  echo "此選項目前僅為佔位，留待未來功能擴充。"
  if declare -F ui_pause >/dev/null 2>&1; then
    ui_pause "按任意鍵返回..." "main"
  else
    echo "按 Enter 返回..."
    read -r _ || true
  fi
  return 0
}

tgdb_print_main_menu() {
  local row code label
  for row in "${TGDB_MAIN_MENU_ROUTES[@]}"; do
    IFS='|' read -r code label _ _ <<< "$row"
    if [ "$code" = "_sep_" ]; then
      echo "$label"
    else
      echo "$code. $label"
    fi
  done
}

tgdb_dispatch_main_menu() {
  local choice="$1"
  local row code label module func

  for row in "${TGDB_MAIN_MENU_ROUTES[@]}"; do
    IFS='|' read -r code label module func <<< "$row"
    [ "$code" = "_sep_" ] && continue
    if [ "$code" = "$choice" ]; then
      if [ -n "$module" ] && [ "$module" != "none" ]; then
        tgdb_load_module "$module" || return 1
      fi
      "$func"
      return $?
    fi
  done

  return 3
}

# ---- CLI 映射表（單一來源）----
# 格式: "spell_key|module|function|min_args|max_args"
# spell_key: 由 src/core/cli.sh:_cli_parse_spell_key 產生，例如 4-1-、5-9-1 等
# shellcheck disable=SC2034 # 供 src/core/cli.sh 引用
TGDB_CLI_REGISTRY_BASE=(
  # 主選單 1, 2 (系統)
  "1--|none|show_system_info|0"
  "2--|none|system_maintenance|0"

  # 主選單 3（系統管理，內部用；不在 CLI help 公開）
  "3-3-|system_admin|system_admin_cli_swap_default|0"
  "3-5-|system_admin|system_admin_cli_timezone_asia_taipei|0"
  "3-7-|system_admin|system_admin_cli_dns_default|0"
  "3-9-|system_admin|system_admin_cli_enable_bbr_fq|0"
  "3-10-|system_admin|system_admin_cli_nftables_init_default|0"
  "3-11-|system_admin|system_admin_cli_install_fail2ban_default|0"
  "3-12-|system_admin|system_admin_cli_change_ssh_port_default|0"

  # 主選單 4 (基礎工具)
  "4-1-|base_tools|install_all_tools_cli|0"
  "4-2-|base_tools|remove_all_tools_cli|0"
  "4-3-|base_tools|install_single_tool|1"
  "4-4-|base_tools|remove_single_tool|1"

  # 主選單 5 (Podman)
  "5-1-|podman|podman_install_cli|0"
  "5-5-|podman|podman_stop_unit_cli|1|-1"
  "5-6-|podman|podman_restart_unit_cli|1|-1"
  "5-7-|podman|podman_remove_unit_cli|1|-1"
  "5-8-|podman|podman_exec_container_cli|1"
  "5-d-|podman|podman_uninstall_cli|1"
  "5-9-1|podman|podman_pull_image_cli|1"
  "5-9-2|podman|podman_remove_image_cli|1|-1"
  "5-9-3|podman|podman_remove_all_images_cli|1"
  "5-10-1|podman|podman_create_network_cli|1"
  "5-10-2|podman|podman_remove_network_cli|1|-1"
  "5-10-3|podman|podman_remove_all_networks_cli|1"
  "5-11-1|podman|podman_create_volume_cli|1"
  "5-11-2|podman|podman_remove_volume_cli|1|-1"
  "5-11-3|podman|podman_remove_all_volumes_cli|1"
  "5-12-0|podman|podman_cleanup_cli|0"

  # 主選單 7 (進階應用)
  # 7 1 x：Rclone
  "7-1-1-|rclone|install_or_update_rclone|0"
  "7-1-d-|rclone|remove_rclone|0"
  "7-1-2-|rclone|add_remote_storage|0"
  "7-1-3-|rclone|edit_rclone_conf|0"
  "7-1-4-|rclone|rclone_mount_cli|2"
  "7-1-5-|rclone|rclone_unmount_cli|1"
  "7-1-6-|rclone|rclone_show_mounts_cli|0"
  "7-1-7-1|rclone|rclone_custom_add_cli|2|-1"
  "7-1-7-2|rclone|rclone_custom_run_saved_cli|1|-1"
  "7-1-7-3|rclone|rclone_custom_list_cli|0"
  "7-1-7-4|rclone|rclone_custom_delete_cli|1"

  # 7 2 x：Nginx
  "7-2-1-|nginx-p|nginx_p_deploy|0"
  "7-2-2-|nginx-p|nginx_p_update|0"
  "7-2-3-|nginx-p|nginx_p_add_reverse_proxy_site_cli|2|3"
  "7-2-4-|nginx-p|nginx_p_add_static_site_cli|1"
  "7-2-5-|nginx-p|nginx_p_update_cert_for_site_cli|1|2"
  "7-2-6-|nginx-p|nginx_p_clear_site_cache|0"
  "7-2-7-|nginx-p|nginx_p_edit_main_conf_cli|0"
  "7-2-8-|nginx-p|nginx_p_edit_site_conf_cli|1"
  "7-2-9-|nginx-p|nginx_p_delete_site_cli|1|-1"
  "7-2-10-|nginx-p|nginx_p_add_custom_cert_cli|1"
  "7-2-11-1|nginx-p|nginx_p_show_systemd_journal_cli|0|1"
  "7-2-11-2|nginx-p|nginx_p_show_access_log_cli|0|1"
  "7-2-11-3|nginx-p|nginx_p_show_error_log_cli|0|1"
  "7-2-11-4|nginx-p|nginx_p_show_modsec_audit_log_cli|0|1"
  "7-2-13-1|nginx-p|nginx_p_waf_show_status_cli|0"
  "7-2-13-2|nginx-p|nginx_p_waf_set_monitor_cli|0"
  "7-2-13-3|nginx-p|nginx_p_waf_set_block_cli|0"
  "7-2-13-4|nginx-p|nginx_p_waf_set_off_cli|0"
  "7-2-13-5|nginx-p|nginx_p_waf_sync_crs_cli|0"
  "7-2-13-6|nginx-p|nginx_p_waf_edit_custom_rules_cli|0"
  "7-2-d-|nginx-p|nginx_p_remove_cli|1|-1"

  # 7 3 x：tmux
  "7-3-1-|tmux|tmux_install_cli|0"
  "7-3-2-|tmux|tmux_create_and_enter_cli|0|1"
  "7-3-3-|tmux|tmux_enter_existing_cli|1"
  "7-3-4-|tmux|tmux_inject_cli|2|-1"
  "7-3-5-|tmux|tmux_kill_cli|1"
  "7-3-6-|tmux|tmux_update_cli|0"
  "7-3-d-|tmux|tmux_uninstall_cli|0|-1"

  # 主選單 8（第三方腳本）僅支援互動模式（TTY），不提供 CLI 路由

  # 主選單 10 (全系統備份)
  "10-1-|backup|backup_create|0"
  "10-2-|backup|backup_restore_latest_cli|0"

)
