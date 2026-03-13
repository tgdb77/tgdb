#!/bin/bash

# Nginx：日誌查看（systemd journal / access.log / error.log / modsec_audit.log）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_NGINX_LOGS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_LOGS_LOADED=1

NGINX_LOGS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/advanced/nginx/nginx_common.sh
source "$NGINX_LOGS_SCRIPT_DIR/nginx_common.sh"

nginx_p_show_systemd_journal_cli() {
    local lines="${1:-200}"
    if ! [[ "$lines" =~ ^[0-9]+$ ]]; then
        tgdb_fail "lines 必須是數字（例：200）" 2 || return $?
    fi
    journalctl --user -u nginx.service -n "$lines" --no-pager || \
    journalctl --user -u container-nginx.service -n "$lines" --no-pager || true
}

nginx_p_show_access_log_cli() {
    local lines="${1:-200}"
    if ! [[ "$lines" =~ ^[0-9]+$ ]]; then
        tgdb_fail "lines 必須是數字（例：200）" 2 || return $?
    fi
    local f="$TGDB_DIR/nginx/logs/access.log"
    if [ ! -f "$f" ]; then
        echo "ℹ️ 找不到日誌檔案：$f"
        echo "   可能原因：尚未有流量，或 Nginx 尚未部署/啟動。"
        return 0
    fi
    tail -n "$lines" "$f" 2>/dev/null || true
}

nginx_p_show_error_log_cli() {
    local lines="${1:-200}"
    if ! [[ "$lines" =~ ^[0-9]+$ ]]; then
        tgdb_fail "lines 必須是數字（例：200）" 2 || return $?
    fi
    local f="$TGDB_DIR/nginx/logs/error.log"
    if [ ! -f "$f" ]; then
        echo "ℹ️ 找不到日誌檔案：$f"
        echo "   可能原因：尚未有流量，或 Nginx 尚未部署/啟動。"
        return 0
    fi
    tail -n "$lines" "$f" 2>/dev/null || true
}

nginx_p_show_modsec_audit_log_cli() {
    local lines="${1:-200}"
    if ! [[ "$lines" =~ ^[0-9]+$ ]]; then
        tgdb_fail "lines 必須是數字（例：200）" 2 || return $?
    fi
    local f="$TGDB_DIR/nginx/logs/modsec_audit.log"
    if [ ! -f "$f" ]; then
        echo "ℹ️ 找不到日誌檔案：$f"
        echo "   可能原因：WAF 尚未啟用、尚未觸發事件，或 Nginx 尚未部署/啟動。"
        return 0
    fi
    tail -n "$lines" "$f" 2>/dev/null || true
}

_tail_access_log() {
  local f="$TGDB_DIR/nginx/logs/access.log"
  _tail_nginx_log_file "Access Log" "$f"
}

_tail_error_log() {
  local f="$TGDB_DIR/nginx/logs/error.log"
  _tail_nginx_log_file "Error Log" "$f"
}

_tail_modsec_audit_log() {
  local f="$TGDB_DIR/nginx/logs/modsec_audit.log"
  _tail_nginx_log_file "ModSecurity Audit Log" "$f"
}

_tail_nginx_log_file() {
  local label="$1"
  local f="$2"

  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi

  if [ ! -f "$f" ]; then
    echo "ℹ️ 找不到日誌檔案：$f"
    echo "   可能原因：尚未有流量，或 Nginx 尚未部署/啟動。"
    ui_pause "按任意鍵返回..."
    return 0
  fi

  echo "追蹤 $label：$f"
  echo "（按任意鍵停止並返回選單）"

  local pid=""
  local old_trap_int old_trap_term
  old_trap_int="$(trap -p INT 2>/dev/null || true)"
  old_trap_term="$(trap -p TERM 2>/dev/null || true)"

  tail -n 200 -f "$f" 2>/dev/null & pid=$!

  # 防止 Ctrl+C 中斷時留下背景 tail，導致回到選單後日誌持續污染終端輸出
  trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' INT TERM

  read -r -n 1 || true
  echo

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  if [ -n "$old_trap_int" ]; then
    eval "$old_trap_int"
  else
    trap - INT
  fi

  if [ -n "$old_trap_term" ]; then
    eval "$old_trap_term"
  else
    trap - TERM
  fi
}

_nginx_kill_stale_log_tails_on_tty() {
  local access_log="$TGDB_DIR/nginx/logs/access.log"
  local error_log="$TGDB_DIR/nginx/logs/error.log"
  local modsec_audit_log="$TGDB_DIR/nginx/logs/modsec_audit.log"

  local my_tty=""
  my_tty="$(ps -o tty= -p "$$" 2>/dev/null | awk '{print $1}' || true)"
  if [ -z "$my_tty" ] || [ "$my_tty" = "?" ]; then
    return 0
  fi

  local pids=""
  pids="$(ps -e -o pid= -o tty= -o command= 2>/dev/null | awk -v tty="$my_tty" -v a="$access_log" -v e="$error_log" -v m="$modsec_audit_log" '
    $2 == tty && $0 ~ /tail -n 200 -f/ && ($0 ~ a || $0 ~ e || $0 ~ m) { print $1 }
  ' || true)"

  [ -n "$pids" ] || return 0
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    kill "$pid" 2>/dev/null || true
  done <<EOF
$pids
EOF
}

nginx_p_tail_journal() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 日誌查看（Quadlet/Nginx）❖"
        echo "=================================="
        echo "1. systemd（容器層）journalctl 最近200行（nginx.service）"
        echo "2. Nginx Access Log（應用層）"
        echo "3. Nginx Error Log（應用層）"
        echo "4. ModSecurity Audit Log（WAF）"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-4]: " c
        case "$c" in
            1)
                journalctl --user -u nginx.service -n 200 --no-pager || \
                journalctl --user -u container-nginx.service -n 200 --no-pager || true
                ui_pause "按任意鍵返回..."
                ;;
            2) _tail_access_log || true ;;
            3) _tail_error_log || true ;;
            4) _tail_modsec_audit_log || true ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}
