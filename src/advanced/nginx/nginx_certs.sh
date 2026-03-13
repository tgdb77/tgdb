#!/bin/bash

# Nginx：憑證相關（Certbot / 自備憑證）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_NGINX_CERTS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_CERTS_LOADED=1

NGINX_CERTS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/advanced/nginx/nginx_common.sh
source "$NGINX_CERTS_SCRIPT_DIR/nginx_common.sh"

_nginx_cert_dns_names_from_crt() {
    local crt="$1"
    [ -f "$crt" ] || return 1
    command -v openssl >/dev/null 2>&1 || return 1

    # 優先取 SAN（DNS:...），若失敗再回退到 CN。
    local san
    san="$(openssl x509 -in "$crt" -noout -ext subjectAltName 2>/dev/null || true)"
    if [ -n "${san:-}" ] && echo "$san" | grep -qi "DNS:"; then
        echo "$san" \
          | tr ',' '\n' \
          | sed -nE 's/^[[:space:]]*DNS:([A-Za-z0-9.*-]+(\.[A-Za-z0-9.*-]+)*)[[:space:]]*$/\1/p'
        return 0
    fi

    openssl x509 -in "$crt" -noout -subject 2>/dev/null \
      | sed -nE 's/^subject=.*CN[[:space:]]*=[[:space:]]*([^,/]+).*$/\1/p'
}

_nginx_cert_has_wildcard() {
    local crt="$1"
    local dns
    while IFS= read -r dns; do
        [ -n "${dns:-}" ] || continue
        case "$dns" in
            \*.*) return 0 ;;
        esac
    done < <(_nginx_cert_dns_names_from_crt "$crt" 2>/dev/null || true)
    return 1
}

_nginx_fqdn_matches_wildcard() {
    local fqdn="$1"
    local wildcard="$2" # 例如：*.example.com

    case "$wildcard" in
        \*.*) ;;
        *) return 1 ;;
    esac

    local suffix="${wildcard#*.}"
    case "$fqdn" in
        *".${suffix}") ;;
        *) return 1 ;;
    esac

    local left="${fqdn%."$suffix"}"
    [ -n "${left:-}" ] || return 1
    case "$left" in
        *.*) return 1 ;; # 泛域名只涵蓋一層子網域
        *) return 0 ;;
    esac
}

_nginx_cert_covers_fqdn() {
    local crt="$1"
    local fqdn="$2"

    local dns
    while IFS= read -r dns; do
        [ -n "${dns:-}" ] || continue
        if [ "$dns" = "$fqdn" ]; then
            return 0
        fi
        if _nginx_fqdn_matches_wildcard "$fqdn" "$dns"; then
            return 0
        fi
    done < <(_nginx_cert_dns_names_from_crt "$crt" 2>/dev/null || true)

    return 1
}

_nginx_list_cert_inventory_lines() {
    local fqdn="${1:-}"
    local cert_dir="$TGDB_DIR/nginx/certs"
    [ -d "$cert_dir" ] || return 0

    local crt key base is_wildcard covers end_ts now_ts days_left
    now_ts="$(date +%s)"

    for crt in "$cert_dir"/*.crt; do
        [ -f "$crt" ] || continue
        base="$(basename "$crt" .crt)"
        key="$cert_dir/${base}.key"
        [ -f "$key" ] || continue

        is_wildcard=0
        if _nginx_cert_has_wildcard "$crt"; then
            is_wildcard=1
        fi

        covers=0
        if [ -n "${fqdn:-}" ] && _nginx_cert_covers_fqdn "$crt" "$fqdn"; then
            covers=1
        fi

        days_left="?"
        end_ts="$(_cert_end_ts "$crt" 2>/dev/null || true)"
        if [ -n "${end_ts:-}" ] && [[ "$end_ts" =~ ^[0-9]+$ ]]; then
            days_left=$(( (end_ts - now_ts) / 86400 ))
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$base" "$crt" "$key" "$is_wildcard" "$covers" "$days_left"
    done
}

_nginx_prompt_select_existing_cert_for_fqdn() {
    local out_var="$1"
    local fqdn="$2"

    if ! ui_is_interactive; then
        return 1
    fi

    local lines=()
    local line has_wildcard=0
    while IFS= read -r line; do
        [ -n "${line:-}" ] || continue
        lines+=("$line")
        if [ "${line##*$'\t'}" != "$line" ]; then
            : # just keep shellcheck happy
        fi
        if [ "$(echo "$line" | awk -F'\t' '{print $4}' 2>/dev/null || echo 0)" = "1" ]; then
            has_wildcard=1
        fi
    done < <(_nginx_list_cert_inventory_lines "$fqdn")

    if [ "$has_wildcard" -ne 1 ] || [ "${#lines[@]}" -eq 0 ]; then
        return 1
    fi

    if ! ui_confirm_yn "偵測到泛域名憑證，是否要改用既有憑證（跳過 Certbot）？(y/N，預設 N，輸入 0 取消): " "N"; then
        local rc=$?
        if [ "$rc" -eq 2 ]; then
            return 2
        fi
        return 1
    fi

    echo "=================================="
    echo "❖ 選擇要使用的憑證 ❖"
    echo "=================================="
    local i
    for ((i=0; i<${#lines[@]}; i++)); do
        local base is_wildcard covers days_left
        base="$(echo "${lines[$i]}" | awk -F'\t' '{print $1}')"
        is_wildcard="$(echo "${lines[$i]}" | awk -F'\t' '{print $4}')"
        covers="$(echo "${lines[$i]}" | awk -F'\t' '{print $5}')"
        days_left="$(echo "${lines[$i]}" | awk -F'\t' '{print $6}')"

        local tag_wildcard="" tag_cover="" tag_days=""
        [ "$is_wildcard" = "1" ] && tag_wildcard="泛域名"
        if [ -n "${fqdn:-}" ]; then
            if [ "$covers" = "1" ]; then
                tag_cover="可覆蓋"
            else
                tag_cover="不覆蓋"
            fi
        fi
        if [ -n "${days_left:-}" ] && [ "$days_left" != "?" ]; then
            tag_days="剩餘 ${days_left} 天"
        fi

        local meta=""
        meta="${tag_wildcard}${tag_wildcard:+ / }${tag_cover}${tag_cover:+ / }${tag_days}"
        [ -n "${meta:-}" ] && meta="（$meta）"
        printf '%2d) %s %s\n' "$((i+1))" "$base" "$meta"
    done
    echo "----------------------------------"
    echo " 0) 不使用（改用 Certbot）"
    echo "=================================="

    local sel
    if ! ui_prompt_index sel "請輸入編號 [0-${#lines[@]}]: " 0 "${#lines[@]}" "0" ""; then
        return 2
    fi

    if [ "$sel" -eq 0 ]; then
        return 1
    fi

    local picked="${lines[$((sel-1))]}"
    local picked_base
    picked_base="$(echo "$picked" | awk -F'\t' '{print $1}')"
    printf -v "$out_var" '%s' "$picked_base"
    return 0
}

_issue_cert_for_domain_p() {
    local fqdn="$1"
    if [ -z "$fqdn" ]; then
        tgdb_fail "FQDN 不可為空" 1 || return $?
    fi

    local log_dir log_file ts
    log_dir="$TGDB_DIR/nginx/logs"
    mkdir -p "$log_dir" 2>/dev/null || true
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    log_file="$log_dir/certbot-${fqdn}-${ts}.log"

    echo "📄 Certbot 輸出將同步記錄到：$log_file"

    if [ ! -f "$SSL_AUTO_RENEW_P" ]; then
        tgdb_fail "找不到憑證工具：$SSL_AUTO_RENEW_P" 1 || return $?
    fi

    local rc=0
    (
        set +e
        CERT_DOMAIN="$fqdn" bash "$SSL_AUTO_RENEW_P" issue 2>&1 | tee -a "$log_file"
        exit "${PIPESTATUS[0]}"
    )
    rc=$?

    if [ "$rc" -ne 0 ]; then
        local msg
        printf -v msg '%s\n%s\n%s\n%s\n%s\n%s\n%s' \
          "申請/驗證憑證失敗（exit code: $rc）" \
          "👉 請檢查：" \
          "   - DNS 是否已指向本機（A/AAAA 記錄）" \
          "   - 外網是否可連到本機 80/TCP（含防火牆/安全組/ISP）" \
          "   - 80/TCP 是否被其他服務佔用（包含 nginx/container）" \
          "   - 你是否在 Cloudflare 橘雲代理下（建議先改 DNS only，或改用 DNS-01）" \
          "📄 失敗詳細輸出：$log_file"
        tgdb_fail "$msg" 1 || return $?
    fi

    return 0
}

_nginx_p_apply_issue_cert_for_fqdn() {
    local fqdn="$1"

    _nginx_prepare_runtime

    echo "執行申請/更新憑證流程：$fqdn ..."
    if ! _issue_cert_for_domain_p "$fqdn"; then
        tgdb_fail "憑證流程失敗：$fqdn" 1 || return $?
    fi
    echo "✅ 已完成 $fqdn 憑證申請/更新"
}

nginx_p_add_custom_cert_cli() {
    local domain="${1:-}"
    if [ -z "$domain" ]; then
        tgdb_fail "用法：nginx_p_add_custom_cert_cli <fqdn>" 2 || return $?
    fi
    if [ ! -t 0 ]; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi
    if ! _is_valid_fqdn "$domain"; then
        tgdb_fail "域名格式不正確（僅允許英數、-、.，且需包含至少一個 .）" 2 || return $?
    fi

    local cert_dir="$TGDB_DIR/nginx/certs"
    mkdir -p "$cert_dir"

    local crt_tmp key_tmp
    crt_tmp="$(mktemp 2>/dev/null || echo "$cert_dir/.${domain}.crt.tmp")"
    key_tmp="$(mktemp 2>/dev/null || echo "$cert_dir/.${domain}.key.tmp")"

    local editor="nano"
    if ! command -v "$editor" >/dev/null 2>&1; then
        if ensure_editor; then
            editor="$EDITOR"
        else
            rm -f "$crt_tmp" "$key_tmp" 2>/dev/null || true
            tgdb_fail "找不到可用的文字編輯器（建議安裝 nano）。" 1 || return $?
        fi
    fi

    echo "接下來會用 $editor 讓你貼上 PEM 內容，請將整段內容貼入後儲存並退出。"
    echo "1/2：編輯 CRT（憑證）"
    "$editor" "$crt_tmp"
    echo "2/2：編輯 KEY（私鑰）"
    "$editor" "$key_tmp"

    if ! grep -q "BEGIN CERTIFICATE" "$crt_tmp" 2>/dev/null || ! grep -q "END CERTIFICATE" "$crt_tmp" 2>/dev/null; then
        rm -f "$crt_tmp" "$key_tmp" 2>/dev/null || true
        tgdb_fail "CRT 格式看起來不正確（找不到 CERTIFICATE 區塊）" 1 || return $?
    fi
    if ! grep -q "BEGIN .*PRIVATE KEY" "$key_tmp" 2>/dev/null || ! grep -q "END .*PRIVATE KEY" "$key_tmp" 2>/dev/null; then
        rm -f "$crt_tmp" "$key_tmp" 2>/dev/null || true
        tgdb_fail "KEY 格式看起來不正確（找不到 PRIVATE KEY 區塊）" 1 || return $?
    fi

    local crt="$cert_dir/${domain}.crt"
    local key="$cert_dir/${domain}.key"

    mv -f "$crt_tmp" "$crt" 2>/dev/null || { cat "$crt_tmp" >"$crt"; rm -f "$crt_tmp" 2>/dev/null || true; }
    mv -f "$key_tmp" "$key" 2>/dev/null || { cat "$key_tmp" >"$key"; rm -f "$key_tmp" 2>/dev/null || true; }

    chmod 600 "$key" 2>/dev/null || true

    echo "✅ 已添加 \"$domain\" 證書"
}

nginx_p_add_custom_cert() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    local domain
    read -r -p "請輸入要匯入憑證的域名（例：api.example.com）: " domain
    if [ -z "${domain:-}" ]; then
        tgdb_err "域名不可為空"
        ui_pause
        return 1
    fi
    if ! _is_valid_fqdn "$domain"; then
        tgdb_err "域名格式不正確（僅允許英數、-、.，且需包含至少一個 .）"
        ui_pause
        return 1
    fi

    local cert_dir="$TGDB_DIR/nginx/certs"
    mkdir -p "$cert_dir"

    local crt_tmp key_tmp
    crt_tmp="$(mktemp 2>/dev/null || echo "$cert_dir/.${domain}.crt.tmp")"
    key_tmp="$(mktemp 2>/dev/null || echo "$cert_dir/.${domain}.key.tmp")"

    local editor="nano"
    if ! command -v "$editor" >/dev/null 2>&1; then
        if ensure_editor; then
            editor="$EDITOR"
        else
            rm -f "$crt_tmp" "$key_tmp" 2>/dev/null || true
            tgdb_err "找不到可用的文字編輯器（建議安裝 nano）。"
            ui_pause
            return 1
        fi
    fi

    echo "接下來會用 $editor 讓你貼上 PEM 內容，請將整段內容貼入後儲存並退出。"
    echo "1/2：編輯 CRT（憑證）"
    "$editor" "$crt_tmp"
    echo "2/2：編輯 KEY（私鑰）"
    "$editor" "$key_tmp"

    if ! grep -q "BEGIN CERTIFICATE" "$crt_tmp" 2>/dev/null || ! grep -q "END CERTIFICATE" "$crt_tmp" 2>/dev/null; then
        rm -f "$crt_tmp" "$key_tmp" 2>/dev/null || true
        tgdb_err "CRT 格式看起來不正確（找不到 CERTIFICATE 區塊）"
        ui_pause
        return 1
    fi
    if ! grep -q "BEGIN .*PRIVATE KEY" "$key_tmp" 2>/dev/null || ! grep -q "END .*PRIVATE KEY" "$key_tmp" 2>/dev/null; then
        rm -f "$crt_tmp" "$key_tmp" 2>/dev/null || true
        tgdb_err "KEY 格式看起來不正確（找不到 PRIVATE KEY 區塊）"
        ui_pause
        return 1
    fi

    local crt="$cert_dir/${domain}.crt"
    local key="$cert_dir/${domain}.key"

    mv -f "$crt_tmp" "$crt" 2>/dev/null || { cat "$crt_tmp" >"$crt"; rm -f "$crt_tmp" 2>/dev/null || true; }
    mv -f "$key_tmp" "$key" 2>/dev/null || { cat "$key_tmp" >"$key"; rm -f "$key_tmp" 2>/dev/null || true; }

    chmod 600 "$key" 2>/dev/null || true

    echo "✅ 已添加 \"$domain\" 證書"
    ui_pause
}
