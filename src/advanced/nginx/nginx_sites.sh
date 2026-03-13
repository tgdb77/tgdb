#!/bin/bash

# Nginx：站點/配置管理（新增站點、編輯、刪除、快取）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_NGINX_SITES_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_SITES_LOADED=1

NGINX_SITES_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/advanced/nginx/nginx_common.sh
source "$NGINX_SITES_SCRIPT_DIR/nginx_common.sh"
# shellcheck source=src/advanced/nginx/nginx_certs.sh
source "$NGINX_SITES_SCRIPT_DIR/nginx_certs.sh"

# --- 核心：站點動作（共用於互動/CLI） ---
_nginx_p_apply_reverse_proxy_site() {
    local fqdn="$1" upstream="$2" cert_base="${3:-}"

    _nginx_prepare_runtime

    if [ -z "${cert_base:-}" ]; then
        echo "申請/驗證憑證（Certbot）..."
        if ! _issue_cert_for_domain_p "$fqdn"; then
            return 1
        fi
    else
        local cert_dir="$TGDB_DIR/nginx/certs"
        if [ ! -f "$cert_dir/${cert_base}.crt" ] || [ ! -f "$cert_dir/${cert_base}.key" ]; then
            tgdb_fail "找不到憑證檔案：$cert_dir/${cert_base}.crt/.key" 1 || return $?
        fi
        echo "✅ 已選用既有憑證：$cert_base（將跳過 Certbot）"
    fi

    local dst_conf="$TGDB_DIR/nginx/configs/${fqdn}.conf"
    local zone
    zone=$(_normalize_domain_as_key "$fqdn")
    local tpl_path="$ROOT_DIR/config/nginx/configs/site.conf"
    mkdir -p "$(dirname "$dst_conf")"
    cp "$tpl_path" "$dst_conf"
    local esc_fqdn esc_upstream esc_zone
    esc_fqdn=$(_esc "$fqdn")
    esc_upstream=$(_esc "$upstream")
    esc_zone=$(_esc "$zone")
    sed -i "s|<fqdn>|$esc_fqdn|g; s|<upstream_host_port>|$esc_upstream|g; s|<domain>|$esc_fqdn|g; s|<domain_s>|$esc_zone|g" "$dst_conf"

    if [ -n "${cert_base:-}" ]; then
        local esc_cert
        esc_cert=$(_esc "$cert_base")
        sed -i -E \
          -e "s|^[[:space:]]*ssl_certificate[[:space:]]+[^;]+;|    ssl_certificate     /etc/nginx/certs/${esc_cert}.crt;|g" \
          -e "s|^[[:space:]]*ssl_certificate_key[[:space:]]+[^;]+;|    ssl_certificate_key /etc/nginx/certs/${esc_cert}.key;|g" \
          "$dst_conf"
    fi

    echo "驗證並重載 Nginx..."
    if _nginx_test_and_reload_podman; then
        echo "✅ 已新增站點 https://$fqdn，正在啟動nginx，可用「查看單元日誌」追蹤進度"
        return 0
    fi

    rm -f "$dst_conf"
    tgdb_fail "配置驗證失敗，已回滾：$fqdn" 1 || return $?
}

_nginx_p_apply_static_site() {
    local fqdn="$1"

    _nginx_prepare_runtime

    echo "申請/驗證憑證（Certbot）..."
    if ! _issue_cert_for_domain_p "$fqdn"; then
        return 1
    fi

    local site_root="$TGDB_DIR/nginx/html/$fqdn"
    mkdir -p "$site_root"
    if [ ! -f "$site_root/index.html" ]; then
        if [ -f "$ROOT_DIR/config/nginx/html/index.html" ]; then
            cp "$ROOT_DIR/config/nginx/html/index.html" "$site_root/index.html"
        else
            cat >"$site_root/index.html" <<EOF
<!doctype html>
<html><head><meta charset="utf-8"><title>$fqdn</title></head>
<body><h1>$fqdn</h1><p>It works.</p></body></html>
EOF
        fi
    fi

    local dst_conf="$TGDB_DIR/nginx/configs/${fqdn}.conf"
    local tpl_path="$ROOT_DIR/config/nginx/configs/static_site.conf"
    mkdir -p "$(dirname "$dst_conf")"
    cp "$tpl_path" "$dst_conf"
    local esc_fqdn
    esc_fqdn=$(_esc "$fqdn")
    sed -i "s|<fqdn>|$esc_fqdn|g" "$dst_conf"

    echo "驗證並重載 Nginx..."
    if _nginx_test_and_reload_podman; then
        echo "✅ 已新增靜態站 https://$fqdn"
        return 0
    fi

    rm -f "$dst_conf"
    tgdb_fail "配置驗證失敗，已回滾：$fqdn" 1 || return $?
}

# --- 站點操作（CLI：非互動版） ---
_nginx_p_switch_site_cert_and_reload() {
    local fqdn="$1"
    local cert_base="$2"

    if [ -z "${fqdn:-}" ] || [ -z "${cert_base:-}" ]; then
        tgdb_fail "內部錯誤：fqdn/cert_base 不可為空" 2 || return $?
    fi

    _nginx_prepare_runtime

    local cert_dir="$TGDB_DIR/nginx/certs"
    local crt="$cert_dir/${cert_base}.crt"
    local key="$cert_dir/${cert_base}.key"
    if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
        tgdb_fail "找不到憑證檔案：$crt / $key" 1 || return $?
    fi

    local conf="$TGDB_DIR/nginx/configs/${fqdn}.conf"
    if [ ! -f "$conf" ]; then
        tgdb_fail "找不到站點配置：$conf" 1 || return $?
    fi

    if command -v openssl >/dev/null 2>&1; then
        if ! _nginx_cert_covers_fqdn "$crt" "$fqdn" 2>/dev/null; then
            tgdb_fail "憑證 \"$cert_base\" 看起來不覆蓋 $fqdn（可用互動模式確認/強制）。" 1 || return $?
        fi
    else
        tgdb_warn "系統缺少 openssl，無法檢查憑證覆蓋範圍，仍將嘗試套用：$cert_base"
    fi

    local bak ts
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    bak="${conf}.bak.${ts}"
    cp "$conf" "$bak"

    local esc_cert
    esc_cert=$(_esc "$cert_base")
    sed -i -E \
      -e "s|^[[:space:]]*ssl_certificate[[:space:]]+[^;]+;|    ssl_certificate     /etc/nginx/certs/${esc_cert}.crt;|g" \
      -e "s|^[[:space:]]*ssl_certificate_key[[:space:]]+[^;]+;|    ssl_certificate_key /etc/nginx/certs/${esc_cert}.key;|g" \
      "$conf"

    if ! grep -qF "/etc/nginx/certs/${cert_base}.crt" "$conf" 2>/dev/null || ! grep -qF "/etc/nginx/certs/${cert_base}.key" "$conf" 2>/dev/null; then
        mv -f "$bak" "$conf" 2>/dev/null || true
        tgdb_fail "站點配置未找到 ssl_certificate/ssl_certificate_key，已回滾：$fqdn" 1 || return $?
    fi

    echo "驗證並重載 Nginx..."
    if _nginx_test_and_reload_podman; then
        rm -f "$bak" 2>/dev/null || true
        echo "✅ 已改用既有憑證並重載：$fqdn（$cert_base）"
        return 0
    fi

    mv -f "$bak" "$conf" 2>/dev/null || true
    _nginx_test_and_reload_podman || true
    tgdb_fail "驗證失敗，已回滾配置：$fqdn" 1 || return $?
}

nginx_p_add_reverse_proxy_site_cli() {
    local fqdn="${1:-}" upstream="${2:-}" cert_base="${3:-}"
    if [ -z "$fqdn" ] || [ -z "$upstream" ]; then
        tgdb_fail "用法：nginx_p_add_reverse_proxy_site_cli <fqdn> <upstream_host_port> [cert_base]" 2 || return $?
    fi
    if ! _is_valid_fqdn "$fqdn"; then
        tgdb_fail "FQDN 格式不正確（僅允許英數、-、.，且需包含至少一個 .）" 2 || return $?
    fi
    if ! _is_valid_upstream_host_port "$upstream"; then
        tgdb_fail "上游格式不正確（請使用 host:port，例：127.0.0.1:8080 或 [::1]:8080）" 2 || return $?
    fi

    if [ -n "${cert_base:-}" ]; then
        local crt="$TGDB_DIR/nginx/certs/${cert_base}.crt"
        if command -v openssl >/dev/null 2>&1; then
            if ! _nginx_cert_covers_fqdn "$crt" "$fqdn" 2>/dev/null; then
                tgdb_fail "憑證 \"$cert_base\" 看起來不覆蓋 $fqdn（CLI 預設不強制）。" 1 || return $?
            fi
        else
            tgdb_warn "系統缺少 openssl，無法檢查憑證覆蓋範圍，仍將嘗試套用：$cert_base"
        fi
    fi

    _nginx_p_apply_reverse_proxy_site "$fqdn" "$upstream" "$cert_base"
}

nginx_p_add_static_site_cli() {
    local fqdn="${1:-}"
    if [ -z "$fqdn" ]; then
        tgdb_fail "用法：nginx_p_add_static_site_cli <fqdn>" 2 || return $?
    fi
    if ! _is_valid_fqdn "$fqdn"; then
        tgdb_fail "FQDN 格式不正確（僅允許英數、-、.，且需包含至少一個 .）" 2 || return $?
    fi

    _nginx_p_apply_static_site "$fqdn"
}

nginx_p_update_cert_for_site_cli() {
    local fqdn="${1:-}" cert_base="${2:-}"
    if [ -z "$fqdn" ]; then
        tgdb_fail "用法：nginx_p_update_cert_for_site_cli <fqdn> [cert_base]" 2 || return $?
    fi
    if ! _is_valid_fqdn "$fqdn"; then
        tgdb_fail "FQDN 格式不正確（僅允許英數、-、.，且需包含至少一個 .）" 2 || return $?
    fi

    if [ -n "${cert_base:-}" ]; then
        _nginx_p_switch_site_cert_and_reload "$fqdn" "$cert_base"
        return $?
    fi

    local conf_dir="$TGDB_DIR/nginx/configs"
    local conf_path="$conf_dir/${fqdn}.conf"
    if [ ! -f "$conf_path" ]; then
        tgdb_fail "找不到站點配置：$conf_path" 1 || return $?
    fi

    _nginx_p_apply_issue_cert_for_fqdn "$fqdn"
}

nginx_p_edit_main_conf_cli() {
    if [ ! -t 0 ]; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi
    nginx_p_edit_main_conf
}

nginx_p_edit_site_conf_cli() {
    local fqdn="${1:-}"
    if [ -z "$fqdn" ]; then
        tgdb_fail "用法：nginx_p_edit_site_conf_cli <fqdn>" 2 || return $?
    fi
    if [ ! -t 0 ]; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi
    if ! _is_valid_fqdn "$fqdn"; then
        tgdb_fail "FQDN 格式不正確（僅允許英數、-、.，且需包含至少一個 .）" 2 || return $?
    fi

    local f="$TGDB_DIR/nginx/configs/${fqdn}.conf"
    if [ ! -f "$f" ]; then
        tgdb_fail "找不到 $f" 1 || return $?
    fi

    if ! ensure_editor; then
        tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || return $?
    fi
    cp "$f" "$f.bak"
    "$EDITOR" "$f"
    if _nginx_test_and_reload_podman; then
        rm -f "$f.bak"
        echo "✅ 已套用修改：$fqdn"
        return 0
    fi

    mv -f "$f.bak" "$f"
    tgdb_fail "驗證失敗，已回滾：$fqdn" 1 || return $?
}

_nginx_delete_site_by_fqdn() {
    local fqdn="$1"

    local conf="$TGDB_DIR/nginx/configs/${fqdn}.conf"
    local removed_conf=0

    local cert_path key_path
    cert_path=""
    key_path=""
    if [ -f "$conf" ]; then
        readarray -t _paths < <(_nginx_site_cert_paths_from_conf "$conf")
        cert_path="${_paths[0]:-}"
        key_path="${_paths[1]:-}"
    fi

    # 若 conf 內沒寫（或格式非預期），回退到慣例路徑。
    if [ -z "${cert_path:-}" ]; then
        cert_path="/etc/nginx/certs/${fqdn}.crt"
    fi
    if [ -z "${key_path:-}" ]; then
        key_path="/etc/nginx/certs/${fqdn}.key"
    fi

    local cert_shared=0
    if _nginx_is_path_shared_in_other_sites "$conf" "$cert_path" || _nginx_is_path_shared_in_other_sites "$conf" "$key_path"; then
        cert_shared=1
    fi

    if [ -f "$conf" ]; then
        local bak ts
        ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
        bak="${conf}.bak.${ts}"
        cp "$conf" "$bak"

        rm -f "$conf"
        rm -rf "$TGDB_DIR/nginx/cache/$fqdn" 2>/dev/null || true

        echo "驗證並重載 Nginx..."
        if _nginx_test_and_reload_podman; then
            rm -f "$bak" 2>/dev/null || true
            removed_conf=1
            echo "✅ 已移除站點配置並重載：$fqdn"
        else
            mv -f "$bak" "$conf" 2>/dev/null || true
            _nginx_test_and_reload_podman || true
            tgdb_fail "Nginx 驗證/重載失敗，已回復配置：$fqdn" 1 || return $?
        fi
    else
        tgdb_warn "未找到站點配置：$conf（仍會嘗試清理快取/靜態目錄/憑證）"
    fi

    # 其餘站點資料：直接刪除（不再二次確認）
    rm -rf "$TGDB_DIR/nginx/cache/$fqdn" 2>/dev/null || true
    rm -f "$TGDB_DIR/nginx/logs/certbot-${fqdn}-"*.log 2>/dev/null || true
    rm -rf "$TGDB_DIR/nginx/html/$fqdn" 2>/dev/null || true

    if [ "$removed_conf" -eq 1 ]; then
        echo "✅ 已刪除站點配置與相關資料：$fqdn"
    else
        echo "✅ 已清理站點相關資料：$fqdn"
    fi

    # 憑證清理策略（無提示）：
    # - 若可判定為 Certbot 管理的單域名憑證，且未被其他站點引用 → 一併刪除
    # - 若疑似自備/共用（泛域名/SAN，多站點引用）→ 跳過刪除，避免誤傷其他站點
    if _nginx_is_certbot_managed_domain "$fqdn"; then
        if [ "$cert_shared" -eq 1 ]; then
            echo "ℹ️ 偵測到憑證可能被其他站點引用，已跳過刪除憑證：$cert_path"
        else
            local cert_file key_file
            cert_file="${cert_path#/etc/nginx/certs/}"
            key_file="${key_path#/etc/nginx/certs/}"

            if [ "$cert_file" = "${fqdn}.crt" ] && [ "$key_file" = "${fqdn}.key" ]; then
                rm -f "$TGDB_DIR/nginx/certs/${cert_file}" "$TGDB_DIR/nginx/certs/${key_file}" 2>/dev/null || true

                local le_dir="$TGDB_DIR/nginx/letsencrypt"
                rm -rf \
                    "$le_dir/live/$fqdn" \
                    "$le_dir/archive/$fqdn" \
                    "$le_dir/renewal/$fqdn.conf" \
                    2>/dev/null || true

                echo "✅ 已清理 Certbot 單域名憑證與續簽資料：$fqdn"
            else
                echo "ℹ️ 站點使用的憑證非預設命名（${fqdn}.crt/.key），已跳過刪除憑證：$cert_path"
            fi
        fi
    else
        echo "ℹ️ 未偵測到 Certbot 管理資料，視為自備/共用憑證，已跳過刪除：$cert_path"
    fi

    return 0
}

nginx_p_delete_site_cli() {
    local fqdn="${1:-}"; shift || true
    if [ "$#" -gt 0 ]; then
        tgdb_fail "用法：t 7 2 9 <fqdn>" 2 || return $?
    fi
    if [ -z "$fqdn" ]; then
        tgdb_fail "用法：t 7 2 9 <fqdn>" 2 || return $?
    fi
    if ! _is_valid_fqdn "$fqdn"; then
        tgdb_fail "FQDN 格式不正確（僅允許英數、-、.，且需包含至少一個 .）" 2 || return $?
    fi

    _nginx_delete_site_by_fqdn "$fqdn"
}

# --- 站點操作 ---
nginx_p_add_reverse_proxy_site() {
    local fqdn upstream
    read -r -p "請輸入精確 FQDN（例：api.example.com）: " fqdn
    [ -z "$fqdn" ] && { tgdb_err "FQDN 不可為空"; ui_pause; return 1; }
    if ! _is_valid_fqdn "$fqdn"; then
        tgdb_err "FQDN 格式不正確（僅允許英數、-、.，且需包含至少一個 .）"
        ui_pause
        return 1
    fi

    read -r -p "請輸入上游 Host:Port（例：127.0.0.1:8080）: " upstream
    [ -z "$upstream" ] && { tgdb_err "上游不可為空"; ui_pause; return 1; }
    if ! _is_valid_upstream_host_port "$upstream"; then
        tgdb_err "上游格式不正確（請使用 host:port，例：127.0.0.1:8080 或 [::1]:8080）"
        ui_pause
        return 1
    fi

    local selected_cert=""
    if _nginx_prompt_select_existing_cert_for_fqdn selected_cert "$fqdn"; then
        if [ -n "${selected_cert:-}" ]; then
            local crt="$TGDB_DIR/nginx/certs/${selected_cert}.crt"
            if ! _nginx_cert_covers_fqdn "$crt" "$fqdn" 2>/dev/null; then
                if ! ui_confirm_yn "⚠️ 你選擇的憑證看起來不覆蓋 $fqdn，仍要繼續使用嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
                    ui_pause
                    return 1
                fi
            fi
        fi
    else
        local rc=$?
        if [ "$rc" -eq 2 ]; then
            ui_pause
            return 0
        fi
    fi

    local rc=0
    if _nginx_p_apply_reverse_proxy_site "$fqdn" "$upstream" "$selected_cert"; then
        rc=0
    else
        rc=$?
    fi
    ui_pause
    return "$rc"
}

nginx_p_add_static_site() {
    local fqdn
    read -r -p "請輸入精確 FQDN（例：static.example.com）: " fqdn
    [ -z "$fqdn" ] && { tgdb_err "FQDN 不可為空"; ui_pause; return 1; }
    if ! _is_valid_fqdn "$fqdn"; then
        tgdb_err "FQDN 格式不正確（僅允許英數、-、.，且需包含至少一個 .）"
        ui_pause
        return 1
    fi

    local rc=0
    if _nginx_p_apply_static_site "$fqdn"; then
        rc=0
    else
        rc=$?
    fi
    ui_pause
    return "$rc"
}

nginx_p_update_cert_for_site() {
    local conf_dir="$TGDB_DIR/nginx/configs"
    if [ ! -d "$conf_dir" ]; then
        tgdb_err "找不到站點配置目錄：$conf_dir"
        ui_pause
        return 1
    fi

    local sites=() fqdn
    while IFS= read -r fqdn; do
        [ -n "$fqdn" ] && sites+=("$fqdn")
    done < <(_list_site_domains)

    if [ "${#sites[@]}" -eq 0 ]; then
        tgdb_warn "尚無任何站點配置（$conf_dir/*.conf）"
        ui_pause
        return 1
    fi

    echo "=================================="
    echo "❖ 選擇要更新憑證的站點 ❖"
    echo "=================================="
    local i
    for ((i=0; i<${#sites[@]}; i++)); do
        printf '%2d) %s\n' "$((i+1))" "${sites[$i]}"
    done
    echo "----------------------------------"
    echo " 0) 返回"
    echo "=================================="

    local sel
    if ! ui_prompt_index sel "請輸入編號 [0-${#sites[@]}]: " 1 "${#sites[@]}" "" 0; then
        return 0
    fi

    fqdn="${sites[$((sel-1))]}"

    local selected_cert=""
    if _nginx_prompt_select_existing_cert_for_fqdn selected_cert "$fqdn"; then
        if [ -n "${selected_cert:-}" ]; then
            local conf="$TGDB_DIR/nginx/configs/${fqdn}.conf"
            if [ ! -f "$conf" ]; then
                tgdb_fail "找不到站點配置：$conf" 1 || { ui_pause; return 1; }
            fi

            local crt="$TGDB_DIR/nginx/certs/${selected_cert}.crt"
            if ! _nginx_cert_covers_fqdn "$crt" "$fqdn" 2>/dev/null; then
                if ! ui_confirm_yn "⚠️ 你選擇的憑證看起來不覆蓋 $fqdn，仍要繼續使用嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
                    ui_pause
                    return 1
                fi
            fi

            local bak
            bak="${conf}.bak.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
            cp "$conf" "$bak"

            local esc_cert
            esc_cert=$(_esc "$selected_cert")
            sed -i -E \
              -e "s|^[[:space:]]*ssl_certificate[[:space:]]+[^;]+;|    ssl_certificate     /etc/nginx/certs/${esc_cert}.crt;|g" \
              -e "s|^[[:space:]]*ssl_certificate_key[[:space:]]+[^;]+;|    ssl_certificate_key /etc/nginx/certs/${esc_cert}.key;|g" \
              "$conf"

            echo "驗證並重載 Nginx..."
            if _nginx_test_and_reload_podman; then
                rm -f "$bak" 2>/dev/null || true
                echo "✅ 已改用既有憑證並重載：$fqdn"
                ui_pause
                return 0
            fi

            mv -f "$bak" "$conf" 2>/dev/null || true
            _nginx_test_and_reload_podman || true
            tgdb_fail "驗證失敗，已回滾配置：$fqdn" 1 || { ui_pause; return 1; }
        fi
    else
        local rc=$?
        if [ "$rc" -eq 2 ]; then
            ui_pause
            return 0
        fi
    fi

    local rc=0
    if _nginx_p_apply_issue_cert_for_fqdn "$fqdn"; then
        rc=0
    else
        rc=$?
    fi
    ui_pause
    return "$rc"
}

nginx_p_clear_site_cache() {
    echo "清除全域快取..."
    rm -rf "$TGDB_DIR/nginx/cache"/* 2>/dev/null || true
    mkdir -p "$TGDB_DIR/nginx/cache"
    _nginx_test_and_reload_podman || true
    echo "✅ 已清除全域快取"
    ui_pause
}

nginx_p_edit_main_conf() {
    local f="$TGDB_DIR/nginx/nginx.conf"
    [ ! -f "$f" ] && { tgdb_err "找不到 $f"; ui_pause; return 1; }
    if ! ensure_editor; then
        tgdb_err "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。"
        ui_pause
        return 1
    fi
    cp "$f" "$f.bak"
    "$EDITOR" "$f"
    if _nginx_test_and_reload_podman; then
        rm -f "$f.bak"
        echo "✅ 已套用修改"
    else
        mv -f "$f.bak" "$f"
        tgdb_err "驗證失敗，已回滾"
    fi
    ui_pause
}

nginx_p_edit_site_conf() {
    local sites=() fqdn
    while IFS= read -r fqdn; do
        [ -n "$fqdn" ] && sites+=("$fqdn")
    done < <(_list_site_domains | sort)

    if [ "${#sites[@]}" -eq 0 ]; then
        tgdb_warn "尚無任何站點配置（${TGDB_DIR}/nginx/configs/*.conf）"
        ui_pause
        return 0
    fi

    echo "=================================="
    echo "❖ 選擇要編輯的站點配置 ❖"
    echo "=================================="
    local i
    for ((i=0; i<${#sites[@]}; i++)); do
        printf '%2d) %s\n' "$((i+1))" "${sites[$i]}"
    done
    echo "----------------------------------"
    echo " 0) 返回"
    echo "=================================="

    local sel
    if ! ui_prompt_index sel "請輸入編號 [0-${#sites[@]}]: " 1 "${#sites[@]}" "" 0; then
        return 0
    fi

    fqdn="${sites[$((sel-1))]}"
    local f="$TGDB_DIR/nginx/configs/${fqdn}.conf"
    [ ! -f "$f" ] && { tgdb_err "找不到 $f"; ui_pause; return 1; }
    if ! ensure_editor; then
        tgdb_err "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。"
        ui_pause
        return 1
    fi
    cp "$f" "$f.bak"
    "$EDITOR" "$f"
    if _nginx_test_and_reload_podman; then
        rm -f "$f.bak"
        echo "✅ 已套用修改"
    else
        mv -f "$f.bak" "$f"
        tgdb_err "驗證失敗，已回滾"
    fi
    ui_pause
}

nginx_p_delete_site() {
    local domains=() fqdn
    while IFS= read -r fqdn; do
        [ -n "$fqdn" ] && domains+=("$fqdn")
    done < <(_list_site_domains | sort)

    if [ "${#domains[@]}" -eq 0 ]; then
        tgdb_warn "尚無任何站點配置（${TGDB_DIR}/nginx/configs/*.conf）"
        ui_pause
        return 0
    fi

    echo "=================================="
    echo "❖ 選擇要刪除的站點 ❖"
    echo "=================================="
    local i
    for ((i=0; i<${#domains[@]}; i++)); do
        printf '%2d) %s\n' "$((i+1))" "${domains[$i]}"
    done
    echo "----------------------------------"
    echo " 0) 返回"
    echo "=================================="

    local sel
    read -r -p "請輸入編號 [0-${#domains[@]}]: " sel
    case "$sel" in
        ''|*[!0-9]*) echo "無效選項"; ui_pause; return 1 ;;
    esac
    if [ "$sel" -eq 0 ]; then
        return 0
    fi
    if [ "$sel" -lt 1 ] || [ "$sel" -gt ${#domains[@]} ]; then
        echo "超出範圍"
        ui_pause
        return 1
    fi

    fqdn="${domains[$((sel-1))]}"
    _nginx_delete_site_by_fqdn "$fqdn" || { ui_pause; return 1; }
    ui_pause
}
