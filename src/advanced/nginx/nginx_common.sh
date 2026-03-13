#!/bin/bash

# Nginx（Podman + Quadlet）共用函式
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_NGINX_COMMON_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_COMMON_LOADED=1

NGINX_COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$NGINX_COMMON_SCRIPT_DIR/../../core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$NGINX_COMMON_SCRIPT_DIR/../../core/quadlet_common.sh"

# 向後相容：本模組歷史上使用 ROOT_DIR/SRC_ROOT 命名
SRC_ROOT="${SRC_ROOT:-$SRC_DIR}"
ROOT_DIR="${ROOT_DIR:-$TGDB_ROOT_DIR}"

NGINX_CONTAINER_NAME="${NGINX_CONTAINER_NAME:-nginx}"
USER_SD_DIR="${USER_SD_DIR:-$HOME/.config/systemd/user}"
SSL_AUTO_RENEW_P="${SSL_AUTO_RENEW_P:-$SRC_DIR/advanced/ssl-auto-renew-p.sh}"
NGINX_WAF_MAINT_P="${NGINX_WAF_MAINT_P:-$SRC_DIR/advanced/nginx/nginx-waf-maint.sh}"

# --- 目錄與樣板 ---
_ensure_layout_and_templates() {

    local dst="$TGDB_DIR/nginx"
    mkdir -p "$dst/configs" "$dst/html" "$dst/logs" "$dst/cache" "$dst/certs" "$dst/modsecurity"

    cp -n  "$ROOT_DIR/config/nginx/nginx.conf"               "$dst/nginx.conf"            2>/dev/null || true
    cp -n  "$ROOT_DIR/config/nginx/configs/default.conf"     "$dst/configs/default.conf" 2>/dev/null || true
    cp -n  "$ROOT_DIR/config/nginx/configs/00-ws-map.conf"   "$dst/configs/00-ws-map.conf" 2>/dev/null || true
    cp -rn "$ROOT_DIR/config/nginx/html/"*                  "$dst/html/"                 2>/dev/null || true

    if [ -f "$dst/configs/site.conf" ] && grep -q '<fqdn>' "$dst/configs/site.conf" 2>/dev/null; then
        rm -f "$dst/configs/site.conf"
    fi
}

_ensure_default_self_signed_cert() {
    local cert_dir="$TGDB_DIR/nginx/certs"
    local crt="$cert_dir/default.crt"
    local key="$cert_dir/default.key"

    if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
        mkdir -p "$cert_dir"
        echo "正在產生預設自簽 ECDSA 憑證（僅供測試）..."
        openssl ecparam -name prime256v1 -genkey -noout -out "$key" >/dev/null 2>&1
        openssl req -x509 -key "$key" -out "$crt" -subj "/CN=default" -days 365 >/dev/null 2>&1
        chmod 600 "$key" 2>/dev/null || true
        echo "✅ 已建立 ${crt} 與 ${key}"
    fi
}

_sanitize_runtime_confs() {
    local runtime_dir="$TGDB_DIR/nginx"
    local conf_dir="$runtime_dir/configs"
    local main_conf="$runtime_dir/nginx.conf"
    local default_conf="$conf_dir/default.conf"

    mkdir -p "$conf_dir" "$runtime_dir/html" "$runtime_dir/logs" "$runtime_dir/cache" "$runtime_dir/certs" "$runtime_dir/modsecurity"

    if [ ! -f "$main_conf" ] && [ -f "$ROOT_DIR/config/nginx/nginx.conf" ]; then
        cp "$ROOT_DIR/config/nginx/nginx.conf" "$main_conf"
    fi
    if [ ! -f "$default_conf" ] && [ -f "$ROOT_DIR/config/nginx/configs/default.conf" ]; then
        cp "$ROOT_DIR/config/nginx/configs/default.conf" "$default_conf"
    fi

    if [ -d "$conf_dir" ]; then
        while IFS= read -r -d '' f; do
            if grep -qE '<fqdn>|<upstream_host_port>|<domain>|<domain_s>' "$f" 2>/dev/null; then
                echo "移除佔位配置：$f"
                rm -f "$f"
            fi
        done < <(find "$conf_dir" -maxdepth 1 -type f -name "*.conf" -print0)
    fi

    if [ -f "$main_conf" ]; then
        sed -i 's/\r$//' "$main_conf" 2>/dev/null || true
    fi
    if [ -d "$conf_dir" ]; then
        while IFS= read -r -d '' f; do
            sed -i 's/\r$//' "$f" 2>/dev/null || true
        done < <(find "$conf_dir" -type f -name "*.conf" -print0)
    fi
}

_nginx_prepare_runtime() {
    _ensure_layout_and_templates
    _ensure_default_self_signed_cert
    _sanitize_runtime_confs
}

_nginx_test_and_reload_podman() {
    if podman exec "$NGINX_CONTAINER_NAME" nginx -t; then
        podman exec "$NGINX_CONTAINER_NAME" nginx -s reload
        return 0
    fi
    return 1
}

_cert_end_ts() {
    local crt="$1"
    [ -f "$crt" ] || return 1
    command -v openssl >/dev/null 2>&1 || return 1

    local end
    end="$(openssl x509 -enddate -noout -in "$crt" 2>/dev/null | cut -d= -f2- || true)"
    [ -n "${end:-}" ] || return 1

    date -d "$end" +%s 2>/dev/null
}

_cert_status_line() {
    local domain="$1"
    local crt="$TGDB_DIR/nginx/certs/${domain}.crt"

    if [ ! -f "$crt" ]; then
        printf '%-35s %s\n' "$domain" "❌ 憑證不存在"
        return 0
    fi

    local end_ts now_ts days end_date
    end_ts="$(_cert_end_ts "$crt" || true)"
    if [ -z "${end_ts:-}" ]; then
        printf '%-35s %s\n' "$domain" "⚠️ 無法解析到期時間"
        return 0
    fi

    now_ts="$(date +%s)"
    days=$(( (end_ts - now_ts) / 86400 ))
    end_date="$(date -d "@$end_ts" +%F 2>/dev/null || echo "")"
    [ -z "${end_date:-}" ] && end_date="$end_ts"

    if [ "$days" -lt 0 ] 2>/dev/null; then
        printf '%-35s %s\n' "$domain" "❌ 已過期（到期：$end_date）"
        return 0
    fi

    if [ "$days" -le 14 ] 2>/dev/null; then
        printf '%-35s %s\n' "$domain" "⚠️ 剩餘 ${days} 天（到期：$end_date）"
        return 0
    fi

    printf '%-35s %s\n' "$domain" "✅ 剩餘 ${days} 天（到期：$end_date）"
    return 0
}

_list_site_domains() {
    local conf_dir="$TGDB_DIR/nginx/configs"
    [ -d "$conf_dir" ] || return 0

    local f base name
    while IFS= read -r -d '' f; do
        base=$(basename "$f")
        name="${base%.conf}"
        if [ "$name" = "default" ] || [[ "$name" != *.* ]]; then
            continue
        fi
        printf '%s\n' "$name"
    done < <(find "$conf_dir" -maxdepth 1 -type f -name "*.conf" -print0 2>/dev/null)
}

_nginx_extract_ssl_value_from_conf() {
    local conf="$1"
    local key="$2"
    [ -f "$conf" ] || return 1

    # 只取未註解的第一筆，並移除結尾的分號與引號。
    awk -v k="$key" '
      /^[[:space:]]*#/ {next}
      $1==k {print $2; exit}
    ' "$conf" 2>/dev/null \
      | sed -e 's/[;"]$//' -e 's/^"//' -e 's/"$//' \
      | head -n1
}

_nginx_site_cert_paths_from_conf() {
    local conf="$1"
    local cert key
    cert="$(_nginx_extract_ssl_value_from_conf "$conf" "ssl_certificate" || true)"
    key="$(_nginx_extract_ssl_value_from_conf "$conf" "ssl_certificate_key" || true)"
    printf '%s\n' "$cert"
    printf '%s\n' "$key"
}

_nginx_is_path_shared_in_other_sites() {
    local self_conf="$1"
    local needle="$2"
    local conf_dir="$TGDB_DIR/nginx/configs"

    [ -n "${needle:-}" ] || return 1
    [ -d "$conf_dir" ] || return 1

    # 只要其他 conf 仍提到同一路徑，就視為可能共用（泛域名/SAN/自備憑證）。
    grep -RInF -- "$needle" "$conf_dir" 2>/dev/null | grep -vF -- "$self_conf" >/dev/null 2>&1
}

_nginx_is_certbot_managed_domain() {
    local fqdn="$1"
    local le_dir="$TGDB_DIR/nginx/letsencrypt"
    [ -d "$le_dir" ] || return 1
    [ -f "$le_dir/renewal/${fqdn}.conf" ] || [ -d "$le_dir/live/$fqdn" ]
}

_nginx_print_sites_cert_summary() {
    local limit="${1:-0}"

    local domains=() d
    while IFS= read -r d; do
        [ -n "$d" ] && domains+=("$d")
    done < <(_list_site_domains)

    if [ "${#domains[@]}" -eq 0 ]; then
        echo "站點/憑證：尚無站點"
        return 0
    fi

    echo "站點/憑證（域名 / 剩餘天數）："
    local i max
    max="${#domains[@]}"
    if [ "$limit" -gt 0 ] 2>/dev/null && [ "$max" -gt "$limit" ] 2>/dev/null; then
        max="$limit"
    fi
    for ((i=0; i<max; i++)); do
        _cert_status_line "${domains[$i]}"
    done
    return 0
}

_normalize_domain_as_key() { echo "$1" | tr '.-' '_'; }

_is_valid_fqdn() {
    local fqdn="$1"
    [[ "$fqdn" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

_is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

_is_valid_upstream_host_port() {
    local upstream="$1"
    local host port

    if [[ "$upstream" =~ ^\\[[0-9A-Fa-f:]+\\]:[0-9]{1,5}$ ]]; then
        port="${upstream##*:}"
        _is_valid_port "$port" || return 1
        return 0
    fi

    if [[ "$upstream" =~ ^[A-Za-z0-9.-]+:[0-9]{1,5}$ ]]; then
        host="${upstream%:*}"
        port="${upstream##*:}"
        [ -n "$host" ] || return 1
        _is_valid_port "$port" || return 1
        return 0
    fi

    return 1
}
