#!/bin/bash

# DERP（derper / Podman + Quadlet）管理模組（Headscale 子模組）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

DERPER_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADSCALE_ADVANCED_DIR="$(cd "$DERPER_MODULE_DIR/../.." && pwd)"
SRC_ROOT="$(cd "$DERPER_MODULE_DIR/../../.." && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

DERPER_CONTAINER_NAME="derper"
DERPER_DEFAULT_PORT="${DERPER_DEFAULT_PORT:-33445}"
DERPER_STUN_PORT="${DERPER_STUN_PORT:-3478}"
DERPER_DEFAULT_REGION_ID="${DERPER_DEFAULT_REGION_ID:-901}"
DERPER_DEFAULT_REGION_NAME="${DERPER_DEFAULT_REGION_NAME:-TGDB DERP}"
DERPER_IMAGE_LATEST="docker.io/fredliang/derper:latest"

_derper_resolved_unit_path() {
  _quadlet_runtime_or_legacy_unit_path "${DERPER_CONTAINER_NAME}.container" "derper"
}

_derper_is_installed() {
  local unit_path
  unit_path="$(_derper_resolved_unit_path 2>/dev/null || true)"
  if [ -n "$unit_path" ] && [ -f "$unit_path" ]; then
    return 0
  fi

  if command -v podman >/dev/null 2>&1; then
    if podman ps -aq --filter "name=^${DERPER_CONTAINER_NAME}$" 2>/dev/null | head -n1 | grep -q .; then
      return 0
    fi
  fi

  return 1
}

_derper_repo_tpl_quadlet() {
  printf '%s\n' "$CONFIG_DIR/derper/quadlet/default.container"
}

_derper_instance_dir() {
  printf '%s\n' "$TGDB_DIR/derper"
}

_derper_env_path() {
  printf '%s\n' "$(_derper_instance_dir)/derper.env"
}

_derper_update_unit_image_to_latest() {
  local unit_path="$1"
  local content updated

  if [ -z "$unit_path" ] || [ ! -f "$unit_path" ]; then
    tgdb_fail "找不到 DERP Quadlet 單元：$unit_path" 1 || return $?
    return 1
  fi

  content="$(cat "$unit_path" 2>/dev/null || true)"
  if [ -z "$content" ]; then
    tgdb_fail "無法讀取 DERP Quadlet 單元：$unit_path" 1 || return $?
    return 1
  fi

  if ! printf '%s\n' "$content" | grep -q '^Image=docker\.io/fredliang/derper:'; then
    tgdb_fail "DERP Quadlet 內找不到可更新的 Image=docker.io/fredliang/derper:* 設定。" 1 || return $?
    return 1
  fi

  updated="$(printf '%s\n' "$content" | sed -E "s|^Image=docker\\.io/fredliang/derper:[^[:space:]]+$|Image=${DERPER_IMAGE_LATEST}|")"
  if ! _write_file "$unit_path" "$updated"; then
    tgdb_fail "無法寫入 DERP Quadlet 單元：$unit_path" 1 || return $?
    return 1
  fi
}

_derper_headscale_config_path() {
  printf '%s\n' "$TGDB_DIR/headscale/etc/config.yaml"
}

_derper_headscale_derpmap_path() {
  printf '%s\n' "$TGDB_DIR/headscale/etc/derpmap.yaml"
}

_derper_headscale_is_local_server() {
  local cfg
  cfg="$(_derper_headscale_config_path)"
  [ -f "$cfg" ]
}

_derper_print_headscale_missing_tips() {
  local cfg
  cfg="$(_derper_headscale_config_path)"

  echo "=================================="
  echo "❖ 無法注入 Headscale（未偵測到本機伺服器）❖"
  echo "=================================="
  echo "找不到：$cfg"
  echo "----------------------------------"
  echo "此功能會修改「Headscale 伺服器」的設定（derpmap + config.yaml）。"
  echo ""
  echo "你可以："
  echo "1) 到 Headscale 伺服器上執行本功能（Headscale 選單第 8 項：注入自建 DERP）。"
  echo "2) 或先在本機部署 Headscale（Headscale 選單第 1 項）。"
  echo ""
  echo "若你只是客戶端節點，要使用新的 DERP："
  echo " - 只要加入 Headscale 即可（Headscale 選單第 6 項），或使用："
  echo "   sudo tailscale up --login-server <server_url> --auth-key <key>"
  echo ""
  echo "提醒：若你使用 Cloudflare 代理/CDN（橘雲），可能導致註冊/認證失敗，建議改為 DNS only（灰雲）。"
  echo "----------------------------------"
  return 0
}

_derper_require_tty() {
  if ! ui_is_interactive; then
    tgdb_fail "DERP 佈署需要互動式終端（TTY）。" 2 || true
    return 2
  fi
  return 0
}

_derper_require_podman_for_quadlet() {
  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 Podman，DERP 需要使用 Podman 啟動 derper。" 1 || true
    echo "請先到主選單：5. Podman 管理 → 安裝/更新 Podman"
    return 1
  fi
  return 0
}

_derper_is_valid_root_domain() {
  local d="${1:-}"
  [ -n "$d" ] || return 1
  case "$d" in
    *" "*|*"/"*|*"\\"*|*":"*) return 1 ;;
  esac
  [[ "$d" == *.* ]] || return 1
  [[ "$d" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1
  return 0
}

_derper_is_valid_fqdn() {
  local fqdn="${1:-}"
  [[ "$fqdn" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

_derper_is_ipv4_addr() {
  local ip="${1:-}"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

_derper_is_ipv6_addr() {
  local ip="${1:-}"
  [[ -n "$ip" ]] || return 1
  [[ "$ip" == *:* ]] || return 1
  [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]]
}

_derper_detect_public_ipv4() {
  local ip=""

  if declare -F get_ipv4_address >/dev/null 2>&1; then
    ip="$(get_ipv4_address 2>/dev/null || true)"
    if _derper_is_ipv4_addr "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  if command -v ip >/dev/null 2>&1; then
    ip="$(
      ip -4 route get 1 2>/dev/null | awk '{
        for (i = 1; i <= NF; i++) {
          if ($i == "src") { print $(i + 1); exit }
        }
      }' || true
    )"
    if _derper_is_ipv4_addr "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  return 1
}

_derper_detect_public_ipv6() {
  local ip=""

  if command -v curl >/dev/null 2>&1; then
    ip="$(
      curl -6 -fsS --connect-timeout 3 --max-time 5 https://api64.ipify.org 2>/dev/null \
        | tr -d '\r\n' \
        | head -n1 \
        || true
    )"
    ip="${ip%%%*}"
    if _derper_is_ipv6_addr "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  if command -v ip >/dev/null 2>&1; then
    ip="$(
      ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{
        for (i = 1; i <= NF; i++) {
          if ($i == "src") {
            gsub(/%.*/, "", $(i + 1))
            print $(i + 1)
            exit
          }
        }
      }' || true
    )"
    ip="${ip%%%*}"
    if _derper_is_ipv6_addr "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  return 1
}

_derper_detect_fqdn_from_env() {
  local env_path
  env_path="$(_derper_env_path)"
  [ -f "$env_path" ] || return 1

  local fqdn
  fqdn="$(awk -F= '
    /^[[:space:]]*DERP_DOMAIN=/ {
      v=$2
      gsub(/\r/, "", v)
      print v
      exit
    }
  ' "$env_path" 2>/dev/null || true)"
  [ -n "${fqdn:-}" ] || return 1
  _derper_is_valid_fqdn "$fqdn" || return 1
  printf '%s\n' "$fqdn"
  return 0
}

_derper_remove_domain_cert_data() {
  local fqdn="${1:-}"
  [ -n "$fqdn" ] || return 1
  _derper_is_valid_fqdn "$fqdn" || return 1

  local crt key
  crt="$TGDB_DIR/nginx/certs/${fqdn}.crt"
  key="$TGDB_DIR/nginx/certs/${fqdn}.key"

  # 保守處理：若 Nginx 站點仍引用此憑證，避免誤刪。
  local conf_dir
  conf_dir="$TGDB_DIR/nginx/configs"
  if [ -d "$conf_dir" ]; then
    if grep -RInF -- "/etc/nginx/certs/${fqdn}.crt" "$conf_dir" >/dev/null 2>&1 || \
       grep -RInF -- "/etc/nginx/certs/${fqdn}.key" "$conf_dir" >/dev/null 2>&1 || \
       grep -RInF -- "${fqdn}.crt" "$conf_dir" >/dev/null 2>&1 || \
       grep -RInF -- "${fqdn}.key" "$conf_dir" >/dev/null 2>&1; then
      tgdb_warn "偵測到 Nginx 站點可能仍在引用 ${fqdn} 憑證，已保留（未刪除）：$crt / $key"
      return 0
    fi
  fi

  local removed_any=0
  if [ -f "$crt" ] || [ -f "$key" ]; then
    rm -f -- "$crt" "$key" 2>/dev/null || true
    removed_any=1
  fi

  # 同步清理 Certbot/Let's Encrypt 資料（若存在）
  local le_dir live_dir archive_dir renewal_conf
  le_dir="$TGDB_DIR/nginx/letsencrypt"
  live_dir="$le_dir/live/$fqdn"
  archive_dir="$le_dir/archive/$fqdn"
  renewal_conf="$le_dir/renewal/${fqdn}.conf"

  if [ -d "$le_dir" ]; then
    # 安全保護：只允許刪除精確對應的 fqdn 子目錄/檔案
    if [ -d "$live_dir" ] && [ "$(basename "$live_dir")" = "$fqdn" ]; then
      rm -rf -- "$live_dir" 2>/dev/null || true
      removed_any=1
    fi
    if [ -d "$archive_dir" ] && [ "$(basename "$archive_dir")" = "$fqdn" ]; then
      rm -rf -- "$archive_dir" 2>/dev/null || true
      removed_any=1
    fi
    if [ -f "$renewal_conf" ] && [ "$(basename "$renewal_conf")" = "${fqdn}.conf" ]; then
      rm -f -- "$renewal_conf" 2>/dev/null || true
      removed_any=1
    fi
  fi

  if [ "$removed_any" -eq 1 ]; then
    echo "✅ 已清理 DERP 網域憑證資料：$fqdn"
  else
    echo "ℹ️ 未偵測到 DERP 網域憑證資料，已略過：$fqdn"
  fi
  return 0
}

_derper_detect_root_domain_from_headscale_config() {
  load_system_config || true

  local f
  f="$(_derper_headscale_config_path)"
  [ -f "$f" ] || return 1

  local url host
  url="$(awk -F'"' '
    /^[[:space:]]*server_url:[[:space:]]*"/ { print $2; exit }
  ' "$f" 2>/dev/null || true)"
  [ -n "${url:-}" ] || return 1

  url="${url#http://}"
  url="${url#https://}"
  host="${url%%/*}"
  host="${host#hs.}"
  _derper_is_valid_root_domain "$host" || return 1
  printf '%s\n' "$host"
  return 0
}

_derper_prompt_root_domain() {
  local __outvar="$1"
  local default_domain=""
  default_domain="$(_derper_detect_root_domain_from_headscale_config 2>/dev/null || true)"

  local input domain
  while true; do
    if [ -n "$default_domain" ]; then
      read -r -e -p "請輸入 root_domain（例：example.com，預設 ${default_domain}，輸入 0 取消）: " input
      domain="${input:-$default_domain}"
    else
      read -r -e -p "請輸入 root_domain（例：example.com，輸入 0 取消）: " domain
    fi

    if [ "$domain" = "0" ]; then
      return 2
    fi

    if ! _derper_is_valid_root_domain "$domain"; then
      tgdb_err "root_domain 格式不正確，請重新輸入（例：example.com）。"
      continue
    fi

    if ! _derper_check_subdomain_dns_for_cert "$domain"; then
      case "$?" in
        2) return 2 ;;
        *) continue ;;
      esac
    fi

    printf -v "$__outvar" '%s' "$domain"
    return 0
  done
}

_derper_dns_ip_list_label() {
  local lines="${1:-}"
  local joined=""

  if [ -z "${lines:-}" ]; then
    printf '%s\n' "未解析到"
    return 0
  fi

  joined="$(printf '%s\n' "$lines" | tgdb_join_lines_csv 2>/dev/null || true)"
  if [ -n "${joined:-}" ]; then
    printf '%s\n' "$joined"
  else
    printf '%s\n' "未解析到"
  fi
}

_derper_dns_contains_ip() {
  local lines="${1:-}"
  local target_ip="${2:-}"
  [ -n "${lines:-}" ] || return 1
  [ -n "${target_ip:-}" ] || return 1
  printf '%s\n' "$lines" | grep -Fx -- "$target_ip" >/dev/null 2>&1
}

_derper_check_subdomain_dns_for_cert() {
  local root_domain="${1:-}"
  local fqdn=""
  local public_ipv4="" public_ipv6=""
  local resolved_ipv4="" resolved_ipv6=""
  local matched=1
  local status=0

  [ -n "${root_domain:-}" ] || return 1
  fqdn="derp.${root_domain}"

  echo "----------------------------------"
  echo "檢查 ${fqdn} DNS 是否已指向本機公網 IP..."

  public_ipv4="$(_derper_detect_public_ipv4 2>/dev/null || true)"
  public_ipv6="$(_derper_detect_public_ipv6 2>/dev/null || true)"
  resolved_ipv4="$(tgdb_resolve_dns_ips "$fqdn" 4 2>/dev/null || true)"
  resolved_ipv6="$(tgdb_resolve_dns_ips "$fqdn" 6 2>/dev/null || true)"

  echo " - 本機公網 IPv4：${public_ipv4:-未偵測到}"
  echo " - 本機公網 IPv6：${public_ipv6:-未偵測到}"
  echo " - DNS A：$(_derper_dns_ip_list_label "$resolved_ipv4")"
  echo " - DNS AAAA：$(_derper_dns_ip_list_label "$resolved_ipv6")"

  if _derper_is_ipv4_addr "$public_ipv4" && _derper_dns_contains_ip "$resolved_ipv4" "$public_ipv4"; then
    matched=0
  fi
  if _derper_is_ipv6_addr "$public_ipv6" && _derper_dns_contains_ip "$resolved_ipv6" "$public_ipv6"; then
    matched=0
  fi

  if [ "$matched" -eq 0 ]; then
    echo "✅ ${fqdn} 已對到本機公網 IP，可繼續申請憑證。"
    return 0
  fi

  tgdb_warn "${fqdn} 目前尚未對到本機公網 IP，憑證申請可能失敗。"
  echo "建議先確認："
  echo " - derp 子域名的 A / AAAA 記錄是否已指向這台機器"
  echo " - 若使用 Cloudflare，請先切到 DNS only（灰雲）"
  echo " - DNS 剛修改時，請稍候數分鐘再重試"

  if ! ui_confirm_yn "仍要使用此 root_domain 繼續部署 DERP 嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
    status=$?
    [ "$status" -eq 2 ] && return 2
    return 1
  fi
  return 0
}

_derper_prompt_region_id() {
  local __outvar="$1"
  local default_id="${2:-$DERPER_DEFAULT_REGION_ID}"

  local input rid
  while true; do
    read -r -e -p "請輸入 DERP Region ID（建議 900-999，預設 ${default_id}，輸入 0 取消）: " input
    rid="${input:-$default_id}"

    if [ "$rid" = "0" ]; then
      return 2
    fi

    if [[ ! "$rid" =~ ^[0-9]+$ ]] || [ "$rid" -le 0 ] 2>/dev/null || [ "$rid" -gt 65535 ] 2>/dev/null; then
      tgdb_err "Region ID 必須是 1-65535 的整數。"
      continue
    fi

    if [ "$rid" -lt 900 ] || [ "$rid" -gt 999 ]; then
      tgdb_warn "提醒：官方建議使用 900-999 作為自建 DERP Region ID（你仍可繼續使用 $rid）。"
    fi

    printf -v "$__outvar" '%s' "$rid"
    return 0
  done
}

_derper_prompt_region_name() {
  local __outvar="$1"
  local default_name="${2:-$DERPER_DEFAULT_REGION_NAME}"

  local input name
  while true; do
    read -r -e -p "請輸入 DERP 名稱（Region Name，預設 \"${default_name}\"，輸入 0 取消）: " input
    name="${input:-$default_name}"

    if [ "$name" = "0" ]; then
      return 2
    fi

    if [ -z "$name" ]; then
      tgdb_err "DERP 名稱不可為空。"
      continue
    fi

    printf -v "$__outvar" '%s' "$name"
    return 0
  done
}

_derper_issue_cert_for_domain_p() {
  local fqdn="$1"
  [ -n "$fqdn" ] || return 1

  local script="$HEADSCALE_ADVANCED_DIR/ssl-auto-renew-p.sh"
  if [ ! -f "$script" ]; then
    tgdb_fail "找不到憑證腳本：$script" 1 || true
    return 1
  fi

  # 安裝/啟用自動續簽 timers（renew-all）
  /bin/bash "$script" setup-timers >/dev/null 2>&1 || true

  CERT_DOMAIN="$fqdn" /bin/bash "$script" issue "$fqdn"
}
