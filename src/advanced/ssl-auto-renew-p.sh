#!/bin/bash

# SSL 憑證自動化（Podman/Quadlet 版）
# 注意：此檔案可能會被其他模組以 bash 直接執行，也可能被 source。
# 為避免污染呼叫端 shell options，僅在「直接執行」時啟用嚴格模式。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

_init_tgdb_dir() {
  # 這支腳本常以子程序或 systemd timer 直接執行，可能不會繼承父程序的 TGDB_DIR。
  # 在 set -u 下，任何未定義變數引用都會直接中斷，因此必須先安全推導 TGDB_DIR。
  if [ -n "${TGDB_DIR:-}" ]; then
    return 0
  fi

  # 以 utils 的標準流程載入（會自動套用預設值），避免重複造輪子與漏設變數。
  load_system_config || true

  # 最後保險：若因環境異常仍未得到 TGDB_DIR，回退到常用預設路徑。
  if [ -z "${TGDB_DIR:-}" ]; then
    TGDB_DIR="${HOME:-/tmp}/.tgdb/app"
  fi
}

_init_tgdb_dir

NGINX_CONTAINER="nginx"
CERTBOT_IMAGE="docker.io/certbot/certbot"
LETSENCRYPT_DIR="${LETSENCRYPT_DIR:-$TGDB_DIR/nginx/letsencrypt}"

USER_SYSTEMD_DIR="$HOME/.config/systemd/user"

_ensure_letsencrypt_dir() {
    mkdir -p "$LETSENCRYPT_DIR" "$LETSENCRYPT_DIR/live" "$LETSENCRYPT_DIR/archive" "$LETSENCRYPT_DIR/renewal" 2>/dev/null || true
}

require_domain() {
    CERT_DOMAIN="${CERT_DOMAIN:-${1:-}}"
    if [ -z "${CERT_DOMAIN:-}" ]; then
        tgdb_fail "請設定環境變數 CERT_DOMAIN 或以參數提供域名" 1 || true
        return 1
    fi
    return 0
}

days_left() {
    local crt="$TGDB_DIR/nginx/certs/$CERT_DOMAIN.crt"
    if [ ! -f "$crt" ]; then echo 0; return 0; fi
    local end_ts
    end_ts=$(openssl x509 -enddate -noout -in "$crt" | cut -d'=' -f2 | xargs -I{} date -d {} +%s)
    local now_ts
    now_ts=$(date +%s)
    echo $(( (end_ts - now_ts) / 86400 ))
}

_stop_nginx_user() {
    _systemctl_user_try stop -- container-nginx.service nginx.service nginx.container || \
    podman stop "$NGINX_CONTAINER" 2>/dev/null || true
}

_start_nginx_user() {
    _systemctl_user_try start --no-block -- nginx.container nginx.service container-nginx.service || \
    _systemctl_user_try start -- nginx.container nginx.service container-nginx.service || \
    podman start "$NGINX_CONTAINER" 2>/dev/null || true
}

_exec_nginx_test_reload() {
    if podman exec "$NGINX_CONTAINER" nginx -t; then
        podman exec "$NGINX_CONTAINER" nginx -s reload || true
        return 0
    fi
    return 1
}

copy_latest_certs_one() {
    local domain="$1"
    local dst_dir="$TGDB_DIR/nginx/certs"
    mkdir -p "$dst_dir"
    cp "$LETSENCRYPT_DIR/live/$domain/fullchain.pem" "$dst_dir/$domain.crt"
    cp "$LETSENCRYPT_DIR/live/$domain/privkey.pem"  "$dst_dir/$domain.key"
    chmod 600 "$dst_dir/$domain.key" || true
}

copy_latest_certs_multi() {
    local live="$LETSENCRYPT_DIR/live"
    [ -d "$live" ] || return 0
    local d
    for d in "$live"/*; do
        [ -d "$d" ] || continue
        local name
        name=$(basename "$d")
        if [ -f "$d/fullchain.pem" ] && [ -f "$d/privkey.pem" ]; then
            copy_latest_certs_one "$name" || true
        fi
    done
}

cmd_issue() {
    require_domain "$@"
    _ensure_letsencrypt_dir
    echo "停止 nginx 以釋放 80..."; _stop_nginx_user || true
    podman run --rm -p 80:80 -v "$LETSENCRYPT_DIR:/etc/letsencrypt" "$CERTBOT_IMAGE" \
        certonly --standalone -d "$CERT_DOMAIN" --agree-tos --register-unsafely-without-email \
        --key-type ecdsa --elliptic-curve secp256r1
    copy_latest_certs_one "$CERT_DOMAIN"
    _start_nginx_user || true
    _exec_nginx_test_reload || true
    echo "✅ issue 完成: $CERT_DOMAIN"
}

cmd_renew() {
    require_domain "$@"
    _ensure_letsencrypt_dir
    local threshold="${RENEW_THRESHOLD_DAYS:-7}"
    local remain
    remain=$(days_left)
    echo "憑證剩餘天數: $remain"
    if [ "$remain" -le "$threshold" ]; then
        echo "進行續簽..."
        _stop_nginx_user || true
        podman run --rm -p 80:80 -v "$LETSENCRYPT_DIR:/etc/letsencrypt" "$CERTBOT_IMAGE" \
            renew --standalone --key-type ecdsa --elliptic-curve secp256r1
        copy_latest_certs_one "$CERT_DOMAIN"
        _start_nginx_user || true
        _exec_nginx_test_reload || true
        echo "✅ 續簽完成"
    else
        echo "尚無需續簽（閾值: ${threshold} 天）"
    fi
}

cmd_renew_all() {
    _ensure_letsencrypt_dir
    echo "進行續簽（全部）..."
    _stop_nginx_user || true
    podman run --rm -p 80:80 -v "$LETSENCRYPT_DIR:/etc/letsencrypt" "$CERTBOT_IMAGE" \
        renew --standalone --key-type ecdsa --elliptic-curve secp256r1 || true
    copy_latest_certs_multi || true
    _start_nginx_user || true
    _exec_nginx_test_reload || true
    echo "✅ 續簽流程（全部）完成"
}

cmd_status() {
    require_domain "$@"
    local remain
    remain=$(days_left)
    echo "${CERT_DOMAIN} 憑證剩餘天數: $remain"
}

cmd_cf_realip_update() {
    local conf="$TGDB_DIR/nginx/configs/00-cf-realip.conf"
    local tmp="$conf.tmp"
    mkdir -p "$(dirname "$conf")"

    local cf_list
    cf_list=$( {
        curl -fsSL https://www.cloudflare.com/ips-v4 &&
        curl -fsSL https://www.cloudflare.com/ips-v6
    } 2>/dev/null ) || { tgdb_fail "無法取得 Cloudflare IP 清單" 1 || true; return 1; }

    {
        echo "# BEGIN CF-REAL-IP (managed by ssl-auto-renew-p.sh)"
        printf '%s\n' "$cf_list" | awk '{print "set_real_ip_from "$0";"}'
        echo "real_ip_header CF-Connecting-IP;"
        echo "real_ip_recursive on;"
        echo "# END CF-REAL-IP"
    } > "$tmp" || { tgdb_fail "寫入 00-cf-realip.conf 失敗" 1 || true; return 1; }

    mv "$tmp" "$conf" || { tgdb_fail "寫入 00-cf-realip.conf 失敗" 1 || true; return 1; }
    if _exec_nginx_test_reload; then :; else tgdb_fail "nginx 驗證/重載失敗" 1 || true; return 1; fi
    echo "✅ 已更新 00-cf-realip.conf 的 Cloudflare 真實 IP 區塊"
}

_write_user_unit() { 
    mkdir -p "$USER_SYSTEMD_DIR"
    printf '%b' "$2" >"$USER_SYSTEMD_DIR/$1"
}

cmd_setup_timers() {
    local renew_svc="tgdb-ssl-renew.service"
    local renew_tim="tgdb-ssl-renew.timer"
    local cf_svc="tgdb-cf-realip-update.service"
    local cf_tim="tgdb-cf-realip-update.timer"
    local script_abs="$SCRIPT_DIR/ssl-auto-renew-p.sh"

    _write_user_unit "$renew_svc" "[Unit]\nDescription=TGDB SSL Renew All (Podman)\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$script_abs\" renew-all\n"
    _write_user_unit "$renew_tim" "[Unit]\nDescription=Daily SSL Renew All at 03:00\n\n[Timer]\nOnCalendar=*-*-* 03:00:00\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"

    _write_user_unit "$cf_svc" "[Unit]\nDescription=TGDB Cloudflare Real-IP Update\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$script_abs\" cf-realip-update\n"
    _write_user_unit "$cf_tim" "[Unit]\nDescription=Monthly CF Real-IP Update at 03:00\n\n[Timer]\nOnCalendar=monthly\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"

    _systemctl_user_try daemon-reload || true
    _systemctl_user_try enable --now -- "$renew_tim" || true
    _systemctl_user_try enable --now -- "$cf_tim" || true
    echo "✅ 已安裝並啟用 timers：$renew_tim, $cf_tim"
}

cmd_remove_timers() {
    local units=(tgdb-ssl-renew.timer tgdb-ssl-renew.service tgdb-cf-realip-update.timer tgdb-cf-realip-update.service)
    for u in "${units[@]}"; do
        _systemctl_user_try disable --now -- "$u" || true
        rm -f "$USER_SYSTEMD_DIR/$u" 2>/dev/null || true
    done
    _systemctl_user_try daemon-reload || true
    echo "✅ 已移除 timers"
}

usage() {
    cat <<USAGE
用法: $0 <issue|renew|renew-all|status|cf-realip-update|setup-timers|remove-timers>
  需域名: CERT_DOMAIN=example.com $0 issue|renew|status
USAGE
}

main() {
    local subcmd="${1:-}"
    case "$subcmd" in
        issue) shift; cmd_issue "$@" ;;
        renew) shift; cmd_renew "$@" ;;
        renew-all) shift; cmd_renew_all "$@" ;;
        status) shift; cmd_status "$@" ;;
        cf-realip-update) shift; cmd_cf_realip_update "$@" ;;
        setup-timers) shift; cmd_setup_timers "$@" ;;
        remove-timers) shift; cmd_remove_timers "$@" ;;
        *) usage; return 1 ;;
    esac
}

if main "$@"; then
  exit 0
else
  exit $?
fi
