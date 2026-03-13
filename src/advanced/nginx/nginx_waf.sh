#!/bin/bash

# Nginx：WAF（ModSecurity + OWASP CRS）管理
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_NGINX_WAF_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_WAF_LOADED=1

NGINX_WAF_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/advanced/nginx/nginx_common.sh
source "$NGINX_WAF_SCRIPT_DIR/nginx_common.sh"

NGINX_WAF_DIR="${NGINX_WAF_DIR:-$TGDB_DIR/nginx/modsecurity}"
NGINX_WAF_MODE_FILE="${NGINX_WAF_MODE_FILE:-$NGINX_WAF_DIR/waf.mode}"
NGINX_WAF_STATE_CONF="${NGINX_WAF_STATE_CONF:-$NGINX_WAF_DIR/tgdb-waf.conf}"
NGINX_WAF_MAIN_CONF="${NGINX_WAF_MAIN_CONF:-$NGINX_WAF_DIR/main.conf}"
NGINX_WAF_ENGINE_CONF="${NGINX_WAF_ENGINE_CONF:-$NGINX_WAF_DIR/modsecurity.conf}"
NGINX_WAF_CUSTOM_RULES_CONF="${NGINX_WAF_CUSTOM_RULES_CONF:-$NGINX_WAF_DIR/custom-rules.conf}"
NGINX_WAF_CRS_DIR="${NGINX_WAF_CRS_DIR:-$NGINX_WAF_DIR/crs}"
NGINX_WAF_CRS_VERSION_FILE="${NGINX_WAF_CRS_VERSION_FILE:-$NGINX_WAF_DIR/crs.version}"
NGINX_WAF_RUNTIME_NGINX_CONF="${NGINX_WAF_RUNTIME_NGINX_CONF:-$TGDB_DIR/nginx/nginx.conf}"

_nginx_waf_is_valid_mode() {
    case "${1:-}" in
        monitor|block|off) return 0 ;;
        *) return 1 ;;
    esac
}

_nginx_waf_mode_to_engine() {
    case "${1:-}" in
        monitor) echo "DetectionOnly" ;;
        block) echo "On" ;;
        off) echo "Off" ;;
        *) echo "DetectionOnly" ;;
    esac
}

_nginx_waf_mode_to_label() {
    case "${1:-}" in
        monitor) echo "監控（DetectionOnly）" ;;
        block) echo "阻擋（On）" ;;
        off) echo "關閉（Off）" ;;
        *) echo "未知" ;;
    esac
}

_nginx_waf_read_mode() {
    local mode=""
    if [ -f "$NGINX_WAF_MODE_FILE" ]; then
        mode="$(head -n1 "$NGINX_WAF_MODE_FILE" 2>/dev/null || true)"
    fi
    if _nginx_waf_is_valid_mode "$mode"; then
        echo "$mode"
    else
        echo "monitor"
    fi
}

_nginx_waf_write_mode() {
    local mode="$1"
    printf '%s\n' "$mode" > "$NGINX_WAF_MODE_FILE"
}

_nginx_waf_update_engine_conf() {
    local mode="$1"
    local engine
    engine="$(_nginx_waf_mode_to_engine "$mode")"

    if grep -qE '^[[:space:]]*SecRuleEngine[[:space:]]+' "$NGINX_WAF_ENGINE_CONF" 2>/dev/null; then
        sed -i -E "s|^[[:space:]]*SecRuleEngine[[:space:]]+.*$|SecRuleEngine ${engine}|g" "$NGINX_WAF_ENGINE_CONF"
    else
        printf '\nSecRuleEngine %s\n' "$engine" >> "$NGINX_WAF_ENGINE_CONF"
    fi
}

_nginx_waf_write_state_conf() {
    local mode="$1"
    if [ "$mode" = "off" ]; then
        cat > "$NGINX_WAF_STATE_CONF" <<'EOF'
# TGDB WAF 狀態：off（完全關閉）
modsecurity off;
EOF
        return 0
    fi

    cat > "$NGINX_WAF_STATE_CONF" <<'EOF'
# TGDB WAF 狀態：on（規則引擎模式見 modsecurity.conf 的 SecRuleEngine）
modsecurity on;
modsecurity_rules_file /etc/nginx/modsecurity/main.conf;
EOF
}

_nginx_waf_patch_runtime_nginx_conf() {
    local mode="$1"
    local conf="$NGINX_WAF_RUNTIME_NGINX_CONF"
    [ -f "$conf" ] || return 1

    # 若不存在 WAF include 行，插入一行註解版，後續再依模式開關。
    if ! grep -qE '^[[:space:]]*#?[[:space:]]*include[[:space:]]+/etc/nginx/modsecurity/tgdb-waf\.conf;[[:space:]]*$' "$conf" 2>/dev/null; then
        if grep -qF 'include /etc/nginx/conf.d/*.conf;' "$conf" 2>/dev/null; then
            sed -i '/include \/etc\/nginx\/conf\.d\/\*\.conf;/i\    # TGDB WAF（ModSecurity）開關檔：由 Nginx WAF 管理功能維護\n    #include /etc/nginx/modsecurity/tgdb-waf.conf;' "$conf"
        else
            printf '\n# TGDB WAF（ModSecurity）開關檔：由 Nginx WAF 管理功能維護\n#include /etc/nginx/modsecurity/tgdb-waf.conf;\n' >> "$conf"
        fi
    fi

    # 若找不到 load_module 行，僅提示，不主動插入（避免插在錯誤區塊位置造成語法錯誤）。
    if ! grep -qE '^[[:space:]]*#?[[:space:]]*load_module[[:space:]]+/usr/lib/nginx/modules/ngx_http_modsecurity_module\.so;[[:space:]]*$' "$conf" 2>/dev/null; then
        tgdb_warn "nginx.conf 缺少 ModSecurity 載入行（/usr/lib/nginx/modules/ngx_http_modsecurity_module.so），WAF 可能無法生效。"
    else
        if [ "$mode" = "off" ]; then
            sed -i -E 's|^[[:space:]]*#?[[:space:]]*load_module[[:space:]]+/usr/lib/nginx/modules/ngx_http_modsecurity_module\.so;[[:space:]]*$|#load_module /usr/lib/nginx/modules/ngx_http_modsecurity_module.so;|g' "$conf"
        else
            sed -i -E 's|^[[:space:]]*#?[[:space:]]*load_module[[:space:]]+/usr/lib/nginx/modules/ngx_http_modsecurity_module\.so;[[:space:]]*$|load_module /usr/lib/nginx/modules/ngx_http_modsecurity_module.so;|g' "$conf"
        fi
    fi

    if [ "$mode" = "off" ]; then
        sed -i -E 's|^[[:space:]]*#?[[:space:]]*include[[:space:]]+/etc/nginx/modsecurity/tgdb-waf\.conf;[[:space:]]*$|    #include /etc/nginx/modsecurity/tgdb-waf.conf;|g' "$conf"
    else
        sed -i -E 's|^[[:space:]]*#?[[:space:]]*include[[:space:]]+/etc/nginx/modsecurity/tgdb-waf\.conf;[[:space:]]*$|    include /etc/nginx/modsecurity/tgdb-waf.conf;|g' "$conf"
    fi
}

_nginx_waf_ensure_runtime_files() {
    mkdir -p "$NGINX_WAF_DIR"

    local tpl_main="$ROOT_DIR/config/nginx/modsecurity/main.conf"
    local tpl_engine="$ROOT_DIR/config/nginx/modsecurity/modsecurity.conf"
    local tpl_custom="$ROOT_DIR/config/nginx/modsecurity/custom-rules.conf"
    if [ -f "$tpl_main" ]; then
        cp -n "$tpl_main" "$NGINX_WAF_MAIN_CONF" 2>/dev/null || true
    fi
    if [ -f "$tpl_engine" ]; then
        cp -n "$tpl_engine" "$NGINX_WAF_ENGINE_CONF" 2>/dev/null || true
    fi
    if [ -f "$tpl_custom" ]; then
        cp -n "$tpl_custom" "$NGINX_WAF_CUSTOM_RULES_CONF" 2>/dev/null || true
    fi

    if [ ! -f "$NGINX_WAF_CUSTOM_RULES_CONF" ]; then
        cat > "$NGINX_WAF_CUSTOM_RULES_CONF" <<'EOF'
# TGDB 自訂規則區
# 你可以在此加入白名單、黑名單或例外規則（SecRule / SecAction）。
EOF
    fi

    # 舊版 main.conf 可能尚未包含 custom-rules，初始化時自動補上。
    if [ -f "$NGINX_WAF_MAIN_CONF" ] && ! grep -qF 'Include /etc/nginx/modsecurity/custom-rules.conf' "$NGINX_WAF_MAIN_CONF" 2>/dev/null; then
        printf '\nInclude /etc/nginx/modsecurity/custom-rules.conf\n' >> "$NGINX_WAF_MAIN_CONF"
    fi

    if [ ! -f "$NGINX_WAF_MODE_FILE" ]; then
        _nginx_waf_write_mode "monitor"
    fi

    if [ ! -f "$NGINX_WAF_STATE_CONF" ]; then
        _nginx_waf_write_state_conf "$(_nginx_waf_read_mode)"
    fi

    if [ ! -f "$NGINX_WAF_CRS_VERSION_FILE" ] && [ -f "$NGINX_WAF_CRS_DIR/.tgdb-crs-version" ]; then
        cp "$NGINX_WAF_CRS_DIR/.tgdb-crs-version" "$NGINX_WAF_CRS_VERSION_FILE" 2>/dev/null || true
    fi
}

_nginx_waf_apply_mode_without_reload() {
    local mode="$1"
    if ! _nginx_waf_is_valid_mode "$mode"; then
        tgdb_fail "WAF 模式無效：$mode（可用：monitor|block|off）" 2 || return $?
    fi

    _nginx_waf_ensure_runtime_files
    _nginx_waf_update_engine_conf "$mode" || return $?
    _nginx_waf_write_state_conf "$mode" || return $?
    _nginx_waf_patch_runtime_nginx_conf "$mode" || { tgdb_fail "套用 WAF 到 nginx.conf 失敗。" 1 || return $?; }
    _nginx_waf_write_mode "$mode" || return $?
}

_nginx_waf_apply_mode_with_reload() {
    local mode="$1"

    local ts
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    local bak_main="$NGINX_WAF_RUNTIME_NGINX_CONF.wafbak.$ts"
    local bak_engine="$NGINX_WAF_ENGINE_CONF.wafbak.$ts"
    local bak_state="$NGINX_WAF_STATE_CONF.wafbak.$ts"
    local bak_mode="$NGINX_WAF_MODE_FILE.wafbak.$ts"

    cp "$NGINX_WAF_RUNTIME_NGINX_CONF" "$bak_main" 2>/dev/null || true
    cp "$NGINX_WAF_ENGINE_CONF" "$bak_engine" 2>/dev/null || true
    cp "$NGINX_WAF_STATE_CONF" "$bak_state" 2>/dev/null || true
    cp "$NGINX_WAF_MODE_FILE" "$bak_mode" 2>/dev/null || true

    if ! _nginx_waf_apply_mode_without_reload "$mode"; then
        rm -f "$bak_main" "$bak_engine" "$bak_state" "$bak_mode" 2>/dev/null || true
        return 1
    fi

    if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$NGINX_CONTAINER_NAME"; then
        if _nginx_test_and_reload_podman; then
            rm -f "$bak_main" "$bak_engine" "$bak_state" "$bak_mode" 2>/dev/null || true
            return 0
        fi

        # 重載失敗則回滾
        if [ -f "$bak_main" ]; then
            mv -f "$bak_main" "$NGINX_WAF_RUNTIME_NGINX_CONF" 2>/dev/null || true
        fi
        if [ -f "$bak_engine" ]; then
            mv -f "$bak_engine" "$NGINX_WAF_ENGINE_CONF" 2>/dev/null || true
        fi
        if [ -f "$bak_state" ]; then
            mv -f "$bak_state" "$NGINX_WAF_STATE_CONF" 2>/dev/null || true
        fi
        if [ -f "$bak_mode" ]; then
            mv -f "$bak_mode" "$NGINX_WAF_MODE_FILE" 2>/dev/null || true
        fi
        _nginx_test_and_reload_podman || true
        tgdb_fail "WAF 模式切換後 Nginx 驗證失敗，已回滾。" 1 || return $?
    fi

    rm -f "$bak_main" "$bak_engine" "$bak_state" "$bak_mode" 2>/dev/null || true
    return 0
}

_nginx_waf_crs_version() {
    if [ -f "$NGINX_WAF_CRS_VERSION_FILE" ]; then
        head -n1 "$NGINX_WAF_CRS_VERSION_FILE" 2>/dev/null || echo "unknown"
        return 0
    fi
    if [ -f "$NGINX_WAF_CRS_DIR/.tgdb-crs-version" ]; then
        head -n1 "$NGINX_WAF_CRS_DIR/.tgdb-crs-version" 2>/dev/null || echo "unknown"
        return 0
    fi
    echo "unknown"
}

nginx_p_waf_prepare_runtime_defaults() {
    _nginx_waf_ensure_runtime_files

    # 首次部署若尚未有 CRS 規則，先拉一次最新版本。
    if [ ! -f "$NGINX_WAF_CRS_DIR/crs-setup.conf" ] || [ ! -d "$NGINX_WAF_CRS_DIR/rules" ]; then
        if [ -f "$NGINX_WAF_MAINT_P" ]; then
            echo "初始化 OWASP CRS 規則（首次部署）..."
            bash "$NGINX_WAF_MAINT_P" sync-crs || tgdb_warn "CRS 初始化失敗，WAF 可能無法正常運作。"
        else
            tgdb_warn "找不到 WAF 維護腳本：$NGINX_WAF_MAINT_P"
        fi
    fi

    # 預設模式：monitor（若使用者已設定則沿用）。
    _nginx_waf_apply_mode_without_reload "$(_nginx_waf_read_mode)"
}

nginx_p_waf_show_status_cli() {
    _nginx_waf_ensure_runtime_files

    local mode engine version
    mode="$(_nginx_waf_read_mode)"
    engine="$(_nginx_waf_mode_to_engine "$mode")"
    version="$(_nginx_waf_crs_version)"

    echo "=== Nginx WAF 狀態 ==="
    echo "模式：$mode（$(_nginx_waf_mode_to_label "$mode")）"
    echo "SecRuleEngine：$engine"
    echo "CRS 版本：$version"
    if [ -f "$NGINX_WAF_CRS_DIR/.tgdb-updated-at" ]; then
        echo "CRS 更新時間（UTC）：$(head -n1 "$NGINX_WAF_CRS_DIR/.tgdb-updated-at" 2>/dev/null || true)"
    fi
    _systemctl_user_try list-timers --all | awk 'NR==1 || /tgdb-nginx-waf-crs-update/' || true
}

nginx_p_waf_set_mode_cli() {
    local mode="${1:-}"
    if ! _nginx_waf_is_valid_mode "$mode"; then
        tgdb_fail "用法：nginx_p_waf_set_mode_cli <monitor|block|off>" 2 || return $?
    fi

    _nginx_prepare_runtime
    _nginx_waf_ensure_runtime_files
    _nginx_waf_apply_mode_with_reload "$mode" || return $?
    echo "✅ 已切換 WAF 模式：$mode（$(_nginx_waf_mode_to_label "$mode")）"
}

nginx_p_waf_set_monitor_cli() { nginx_p_waf_set_mode_cli "monitor"; }
nginx_p_waf_set_block_cli() { nginx_p_waf_set_mode_cli "block"; }
nginx_p_waf_set_off_cli() { nginx_p_waf_set_mode_cli "off"; }

nginx_p_waf_sync_crs_cli() {
    _nginx_prepare_runtime
    _nginx_waf_ensure_runtime_files
    if [ ! -f "$NGINX_WAF_MAINT_P" ]; then
        tgdb_fail "找不到 WAF 維護腳本：$NGINX_WAF_MAINT_P" 1 || return $?
    fi
    bash "$NGINX_WAF_MAINT_P" sync-crs
}

nginx_p_waf_edit_custom_rules_cli() {
    if [ ! -t 0 ]; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _nginx_prepare_runtime
    _nginx_waf_ensure_runtime_files

    if ! ensure_editor; then
        tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || return $?
    fi

    local f="$NGINX_WAF_CUSTOM_RULES_CONF"
    local bak
    bak="${f}.bak.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    cp "$f" "$bak"

    "$EDITOR" "$f"

    if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$NGINX_CONTAINER_NAME"; then
        if _nginx_test_and_reload_podman; then
            rm -f "$bak" 2>/dev/null || true
            echo "✅ 已套用自訂規則並重載 Nginx"
            return 0
        fi

        mv -f "$bak" "$f" 2>/dev/null || true
        _nginx_test_and_reload_podman || true
        tgdb_fail "自訂規則語法或套用失敗，已回滾。" 1 || return $?
    fi

    rm -f "$bak" 2>/dev/null || true
    echo "ℹ️ Nginx 容器尚未啟動，已儲存自訂規則；啟動後會在 reload 時驗證。"
}

nginx_p_waf_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ WAF（ModSecurity + OWASP CRS）❖"
        echo "=================================="
        nginx_p_waf_show_status_cli
        echo "----------------------------------"
        echo "1. 重新整理狀態"
        echo "2. 切換為監控模式（DetectionOnly，預設）"
        echo "3. 切換為阻擋模式（On）"
        echo "4. 關閉 WAF（Off）"
        echo "5. 立即更新 OWASP CRS 規則"
        echo "6. 編輯自訂規則（custom-rules.conf）"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-6]: " c
        case "$c" in
            1) ui_pause "按任意鍵返回..." ;;
            2) nginx_p_waf_set_monitor_cli || true; ui_pause "按任意鍵返回..." ;;
            3) nginx_p_waf_set_block_cli || true; ui_pause "按任意鍵返回..." ;;
            4) nginx_p_waf_set_off_cli || true; ui_pause "按任意鍵返回..." ;;
            5) nginx_p_waf_sync_crs_cli || true; ui_pause "按任意鍵返回..." ;;
            6) nginx_p_waf_edit_custom_rules_cli || true; ui_pause "按任意鍵返回..." ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}
