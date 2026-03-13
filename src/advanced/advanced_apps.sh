#!/bin/bash

# 進階應用：集中入口（Rclone / Nginx / tmux / GameServer）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"

_advanced_load_module() {
  local module="$1"
  [ -n "$module" ] || return 0

  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "$module"
    return $?
  fi

  local path="$SCRIPT_DIR/${module}.sh"
  if [ ! -f "$path" ]; then
    path="$SRC_ROOT/${module}.sh"
  fi
  if [ ! -f "$path" ]; then
    tgdb_fail "找不到模組：$path" 1 || return $?
  fi
  # shellcheck disable=SC1090 # 模組由參數決定，於執行期載入
  source "$path"
}

advanced_apps_menu() {
  if ! ui_is_interactive; then
    tgdb_fail "進階應用需要互動式終端（TTY）。" 2 || return $?
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ 進階應用 ❖"
    echo "=================================="
    echo "1. Rclone 管理"
    echo "2. Nginx 管理"
    echo "3. tmux 工作區管理"
    echo "4. Cloudflare Tunnel 管理"
    echo "5. Headscale / DERP 管理"
    echo "6. 數據庫管理"
    echo "7. Game Server（LinuxGSM）"
    echo "----------------------------------"
    echo "0. 返回主選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-7]: " choice

    case "$choice" in
      1)
        _advanced_load_module "rclone" || { ui_pause "按任意鍵返回..."; continue; }
        rclone_menu || true
        ;;
      2)
        _advanced_load_module "nginx-p" || { ui_pause "按任意鍵返回..."; continue; }
        nginx_p_menu || true
        ;;
      3)
        _advanced_load_module "tmux" || { ui_pause "按任意鍵返回..."; continue; }
        tmux_menu || true
        ;;
      4)
        _advanced_load_module "cloudflared-p" || { ui_pause "按任意鍵返回..."; continue; }
        cloudflared_p_menu || true
        ;;
      5)
        _advanced_load_module "headscale-p" || { ui_pause "按任意鍵返回..."; continue; }
        headscale_p_menu || true
        ;;
      6)
        _advanced_load_module "dbadmin-p" || { ui_pause "按任意鍵返回..."; continue; }
        dbadmin_p_menu || true
        ;;
      7)
        _advanced_load_module "gameserver-p" || { ui_pause "按任意鍵返回..."; continue; }
        gameserver_p_menu || true
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
