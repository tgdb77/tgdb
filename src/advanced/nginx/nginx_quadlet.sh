#!/bin/bash

# Nginx：Quadlet / systemd --user 管理
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_NGINX_QUADLET_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_QUADLET_LOADED=1

NGINX_QUADLET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/advanced/nginx/nginx_common.sh
source "$NGINX_QUADLET_SCRIPT_DIR/nginx_common.sh"

_render_quadlet_to_user() {
    _ensure_user_units_dir
    local tpl="$ROOT_DIR/config/nginx/quadlet/default.container"
    local out
    out="$(rm_user_unit_path "nginx.container")"
    if [ ! -f "$tpl" ]; then
        tgdb_fail "找不到 Quadlet 樣板：$tpl" 1 || return $?
    fi
    local esc_tgdb
    esc_tgdb=$(_esc "$TGDB_DIR")
    sed "s|\${TGDB_DIR}|$esc_tgdb|g" "$tpl" >"$out"
    echo "$out"
}

_systemd_user_try_enable_now() {
    local name="${1:-nginx}"
    _systemctl_user_try enable --now --no-block -- "$name.container" "$name.service" "container-$name.service" || \
    _systemctl_user_try enable --now -- "$name.container" "$name.service" "container-$name.service" || \
    _systemctl_user_try start --no-block -- "$name.service" "container-$name.service" || \
    _systemctl_user_try start -- "$name.service" "container-$name.service" || true
}

_systemd_user_try_stop() {
    local name="${1:-nginx}"
    _systemctl_user_try stop --no-block -- "$name.container" "$name.service" "container-$name.service" || \
    _systemctl_user_try stop -- "$name.container" "$name.service" "container-$name.service" || true
}

_systemd_user_status_hint() {
    echo "使用以下指令檢視狀態與日誌："
    echo "  systemctl --user status nginx.service"
    echo "  journalctl --user -u nginx.service -n 200 --no-pager"
    echo "  # 若你的環境單元名稱不同，可再試：container-nginx.service"
}

# --- 部署/更新/移除 ---
nginx_p_deploy() {
    echo "=== 部署 Nginx（Podman + Quadlet） ==="
    _nginx_prepare_runtime
    if declare -F nginx_p_waf_prepare_runtime_defaults >/dev/null 2>&1; then
        nginx_p_waf_prepare_runtime_defaults || true
    fi

    local unit_file
    unit_file=$(_render_quadlet_to_user)
    echo "已寫入 Quadlet 單元：$unit_file"

    _systemctl_user_try daemon-reload || true
    _systemd_user_try_enable_now nginx

    sleep 1
    if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$NGINX_CONTAINER_NAME"; then
        podman exec "$NGINX_CONTAINER_NAME" nginx -t || true
        echo "✅ 正在啟動nginx，可用「查看單元日誌」追蹤進度"
    else
        tgdb_warn "容器尚未就緒，輸出日誌供參考："
        journalctl --user -u container-nginx.service -n 200 --no-pager || true
    fi
    echo "設定自動任務（timers）..."
    bash "$SSL_AUTO_RENEW_P" setup-timers || true
    if [ -f "$NGINX_WAF_MAINT_P" ]; then
        bash "$NGINX_WAF_MAINT_P" setup-timer || true
    fi
    _systemd_user_status_hint
    ui_pause "按任意鍵返回..."
}

nginx_p_update() {
    echo "=== 更新 Nginx（podman pull + systemd --user restart） ==="
    podman pull docker.io/kjlion/nginx:alpine || true
    _systemctl_user_try restart --no-block -- nginx.container nginx.service container-nginx.service || \
    _systemctl_user_try restart -- nginx.container nginx.service container-nginx.service || true
    podman exec "$NGINX_CONTAINER_NAME" nginx -t || true
    echo "✅ 更新流程完成，正在啟動nginx，可用「查看單元日誌」追蹤進度"
    ui_pause "按任意鍵返回..."
}

nginx_p_remove() {
    echo "=== 完全移除 Nginx（Quadlet） ==="
    _systemd_user_try_stop nginx
    _systemctl_user_try disable --now -- nginx.container nginx.service container-nginx.service || true
    rm -f "$(rm_user_unit_path "nginx.container")" 2>/dev/null || true
    _systemctl_user_try daemon-reload || true
    bash "$SSL_AUTO_RENEW_P" remove-timers || true
    if [ -f "$NGINX_WAF_MAINT_P" ]; then
        bash "$NGINX_WAF_MAINT_P" remove-timer || true
    fi
    if ui_confirm_yn "是否同時移除 ${TGDB_DIR}/nginx 目錄？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        rm -rf "$TGDB_DIR/nginx"
        echo "✅ 已刪除 ${TGDB_DIR}/nginx"
    fi
    ui_pause "按任意鍵返回..."
}

# --- CLI：完全移除（非互動版，高風險） ---
# 用法：t 7 2 d <del_dir_flag>
# - del_dir_flag：0=清理（刪除）$TGDB_DIR/nginx；1=保留 $TGDB_DIR/nginx
nginx_p_remove_cli() {
    local del_dir_flag="${1:-}"; shift || true
    if [ "$#" -gt 0 ]; then
        tgdb_fail "用法：t 7 2 d <del_dir_flag:0|1>" 2 || return $?
    fi

    case "$del_dir_flag" in
        0|1) ;;
        *) tgdb_fail "用法：t 7 2 d <del_dir_flag:0|1>" 2 || return $? ;;
    esac

    echo "=== 完全移除 Nginx（Quadlet / timers /（可選）資料目錄） ==="

    _systemd_user_try_stop nginx
    _systemctl_user_try disable --now -- nginx.container nginx.service container-nginx.service || true
    rm -f "$(rm_user_unit_path "nginx.container")" 2>/dev/null || true
    _systemctl_user_try daemon-reload || true
    bash "$SSL_AUTO_RENEW_P" remove-timers || true
    if [ -f "$NGINX_WAF_MAINT_P" ]; then
        bash "$NGINX_WAF_MAINT_P" remove-timer || true
    fi

    if [ "$del_dir_flag" = "0" ]; then
        rm -rf "$TGDB_DIR/nginx" 2>/dev/null || true
        if [ -d "$TGDB_DIR/nginx" ]; then
            tgdb_fail "無法刪除 ${TGDB_DIR}/nginx（可能權限不足）" 1 || return $?
        fi
        echo "✅ 已刪除 ${TGDB_DIR}/nginx"
    else
        echo "ℹ️ 已保留 ${TGDB_DIR}/nginx"
    fi

    echo "✅ 已完成移除流程"
}
