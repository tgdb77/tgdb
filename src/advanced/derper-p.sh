#!/bin/bash

# DERP（derper / Podman + Quadlet）管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

DERPER_CONTAINER_NAME="derper"
DERPER_DEFAULT_PORT="${DERPER_DEFAULT_PORT:-33445}"
DERPER_STUN_PORT="${DERPER_STUN_PORT:-3478}"
DERPER_DEFAULT_REGION_ID="${DERPER_DEFAULT_REGION_ID:-901}"
DERPER_DEFAULT_REGION_NAME="${DERPER_DEFAULT_REGION_NAME:-TGDB DERP}"

_derper_resolved_unit_path() {
  _quadlet_runtime_or_legacy_unit_path "${DERPER_CONTAINER_NAME}.container" "derper"
}

_derper_repo_tpl_env() {
  printf '%s\n' "$CONFIG_DIR/derper/configs/derper.env.example"
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

  local script="$SCRIPT_DIR/ssl-auto-renew-p.sh"
  if [ ! -f "$script" ]; then
    tgdb_fail "找不到憑證腳本：$script" 1 || true
    return 1
  fi

  # 安裝/啟用自動續簽 timers（renew-all）
  /bin/bash "$script" setup-timers >/dev/null 2>&1 || true

  CERT_DOMAIN="$fqdn" /bin/bash "$script" issue "$fqdn"
}

_derper_write_env() {
  local fqdn="$1" verify_url="$2"
  local env_path
  env_path="$(_derper_env_path)"
  mkdir -p "$(dirname "$env_path")"

  cat >"$env_path" <<EOF
# derper 環境變數（由 TGDB 生成）
DERP_DOMAIN=${fqdn}
DERP_CERT_MODE=manual
DERP_CERT_DIR=/app/certs
DERP_ADDR=:443
DERP_STUN=true
DERP_STUN_PORT=${DERPER_STUN_PORT}
DERP_HTTP_PORT=-1

# Headscale 官方建議：使用 /verify 作為驗證端點（避免 tailscaled 本地 API 依賴）
DERP_VERIFY_CLIENT_URL=${verify_url}
EOF
  echo "✅ 已寫入：$env_path"
  return 0
}

_derper_render_quadlet_unit() {
  local instance_dir="$1" derp_port="$2"
  local tpl
  tpl="$(_derper_repo_tpl_quadlet)"
  if [ ! -f "$tpl" ]; then
    tgdb_fail "找不到 Quadlet 範本：$tpl" 1 || true
    return 1
  fi

  local content
  content="$(cat "$tpl")"

  content="$(printf '%s' "$content" | sed \
    -e "s|\\\${container_name}|$(_esc "$DERPER_CONTAINER_NAME")|g" \
    -e "s|\\\${instance_dir}|$(_esc "$instance_dir")|g" \
    -e "s|\\\${TGDB_DIR}|$(_esc "$TGDB_DIR")|g" \
    -e "s|\\\${derp_port}|$(_esc "$derp_port")|g" \
  )"

  printf '%s' "$content"
  return 0
}

_derper_firewall_maybe_open_ports() {
  local derp_port="$1"

  local nft_bin=""
  nft_bin="$(type -P nft 2>/dev/null || true)"
  if [ -z "${nft_bin:-}" ]; then
    for nft_bin in /usr/sbin/nft /usr/bin/nft /sbin/nft /bin/nft /usr/local/sbin/nft /usr/local/bin/nft; do
      [ -x "$nft_bin" ] && break
      nft_bin=""
    done
  fi

  if [ -z "${nft_bin:-}" ]; then
    tgdb_warn "未偵測到 nftables，請自行確認防火牆已放行：TCP/${derp_port} 與 UDP/${DERPER_STUN_PORT}，以及申請憑證需要的 TCP/80。"
    return 0
  fi

  tgdb_info "偵測到 nftables：$nft_bin"
  if ! ui_confirm_yn "要嘗試自動放行 TCP/${derp_port} 與 UDP/${DERPER_STUN_PORT}（table inet tgdb_net）嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    [ "$?" -eq 2 ] && return 0
    return 0
  fi

  if ! require_root; then
    tgdb_warn "缺少 root/sudo 權限，已略過自動放行。"
    return 0
  fi

  if ! sudo nft list table inet tgdb_net >/dev/null 2>&1; then
    tgdb_warn "找不到 table inet tgdb_net，已略過自動放行。請自行確認防火牆規則。"
    return 0
  fi

  # 依 nftables.sh 的預設 set 命名：allowed_tcp_ports / allowed_udp_ports
  # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
  sudo nft add element inet tgdb_net allowed_tcp_ports { "$derp_port" } 2>/dev/null || true
  # shellcheck disable=SC1083 # nft 語法使用 { }，ShellCheck 會誤判
  sudo nft add element inet tgdb_net allowed_udp_ports { "$DERPER_STUN_PORT" } 2>/dev/null || true
  echo "✅ 已嘗試放行：TCP/${derp_port}、UDP/${DERPER_STUN_PORT}"
  return 0
}

_derper_region_code_from_id() {
  local rid="${1:-}"
  printf 'TGDB-%s\n' "$rid"
  return 0
}

_derper_node_name_from_region_id() {
  local rid="${1:-}"
  printf '%s-%s\n' "$DERPER_CONTAINER_NAME" "$rid"
  return 0
}

_derper_render_derpmap_region_block() {
  local root_domain="$1" derp_port="$2" region_id="$3" region_name="$4"
  local public_ipv4="${5:-}" public_ipv6="${6:-}"

  local region_code node_name hostname
  region_code="$(_derper_region_code_from_id "$region_id")"
  node_name="$(_derper_node_name_from_region_id "$region_id")"
  hostname="derp.${root_domain}"

  cat <<EOF
  ${region_id}:
    regionid: ${region_id}
    regioncode: "${region_code}"
    regionname: "${region_name}"
    nodes:
      - name: "${node_name}"
        regionid: ${region_id}
        hostname: "${hostname}"
EOF
  if _derper_is_ipv4_addr "$public_ipv4"; then
    printf '        ipv4: "%s"\n' "$public_ipv4"
  fi
  if _derper_is_ipv6_addr "$public_ipv6"; then
    printf '        ipv6: "%s"\n' "$public_ipv6"
  fi
  cat <<EOF
        derpport: ${derp_port}
        stunport: ${DERPER_STUN_PORT}
EOF
}

_derper_ensure_derpmap_file_base() {
  local out="$1"
  mkdir -p "$(dirname "$out")"

  if [ -f "$out" ]; then
    # 若使用者已有自訂 derpmap，保留內容；後續只做 upsert。
    return 0
  fi

  cat >"$out" <<EOF
# 自建 DERP map（由 TGDB 生成，供 headscale 的 derp.paths 使用）
#
# 提醒：
# - Region ID 官方建議用 900–999（Tailscale 保留給使用者自建）
# - 若 DERP 不走 443/tcp（本計畫可能使用 ${DERPER_DEFAULT_PORT}/tcp），請務必設定 derpport

regions:
EOF
  return 0
}

_derper_upsert_derpmap_yaml() {
  local root_domain="$1" derp_port="$2" region_id="$3" region_name="$4"
  local public_ipv4="${5:-}" public_ipv6="${6:-}"
  local out tmp
  out="$(_derper_headscale_derpmap_path)"
  tmp="${out}.tmp"

  _derper_ensure_derpmap_file_base "$out" || return 1

  local block
  block="$(_derper_render_derpmap_region_block "$root_domain" "$derp_port" "$region_id" "$region_name" "$public_ipv4" "$public_ipv6")"

  # 目標：
  # - 若 regions: 下已有相同 region_id，取代該 block
  # - 否則新增到 regions: 底下（同一份 derpmap 可包含多個 region/node）
  awk -v rid="$region_id" -v block="$block" '
    function is_region_header(line) {
      return (line ~ /^[[:space:]]{2}[0-9]+:[[:space:]]*$/)
    }
    function is_target_header(line) {
      return (line ~ ("^[[:space:]]{2}" rid ":[[:space:]]*$"))
    }
    BEGIN {
      in_regions = 0
      in_target = 0
      inserted = 0
      saw_regions = 0
    }
    /^regions:[[:space:]]*$/ {
      saw_regions = 1
      in_regions = 1
      print
      next
    }
    in_target == 1 {
      # 直到下一個 region header 或離開 regions 區塊才結束 skip
      if (is_region_header($0)) {
        if (inserted == 0) {
          print block
          inserted = 1
        }
        in_target = 0
        print
        next
      }
      # 若遇到非縮排 key（離開 regions），先補上 block 再繼續輸出
      if ($0 ~ /^[a-zA-Z0-9_]+:[[:space:]]*/ && $0 !~ /^[[:space:]]/) {
        if (inserted == 0) {
          print block
          inserted = 1
        }
        in_target = 0
        in_regions = 0
        print
        next
      }
      next
    }
    in_regions == 1 && is_target_header($0) {
      in_target = 1
      next
    }
    # 插入：regions: 之後若沒有任何 region header，也允許直接加在第一個非空行前
    in_regions == 1 && inserted == 0 && $0 !~ /^[[:space:]]/ {
      print block
      inserted = 1
      in_regions = 0
      print
      next
    }
    { print }
    END {
      if (saw_regions == 0) {
        print ""
        print "regions:"
        print block
        inserted = 1
      } else if (in_target == 1 && inserted == 0) {
        print block
        inserted = 1
      } else if (saw_regions == 1 && inserted == 0) {
        print block
        inserted = 1
      }
    }
  ' "$out" >"$tmp" || { rm -f "$tmp" 2>/dev/null || true; return 1; }

  mv "$tmp" "$out" || return 1
  echo "✅ 已更新：$out（已寫入/更新 Region ID：${region_id}）"
  return 0
}

_derper_patch_headscale_config_derp() {
  local config_path="$1" force_only="$2"
  local tmp="${config_path}.tmp"
  local derpmap_path='/etc/headscale/derpmap.yaml'

  awk -v force="$force_only" -v dpath="$derpmap_path" '
    function insert_urls_paths() {
      if (force == 1 && inserted_urls == 0) {
        print "  urls: []"
        inserted_urls = 1
      }
      if (inserted_paths == 0) {
        print "  paths:"
        print "    - \"" dpath "\""
        inserted_paths = 1
      }
    }
    BEGIN {
      in_derp = 0
      inserted_paths = 0
      inserted_urls = 0
      skip_paths = 0
      skip_urls = 0
    }
    /^derp:[[:space:]]*$/ {
      in_derp = 1
      inserted_paths = 0
      inserted_urls = 0
      skip_paths = 0
      skip_urls = 0
      print
      next
    }
    in_derp == 1 && $0 ~ /^[a-zA-Z0-9_]+:[[:space:]]*/ && $0 !~ /^derp:/ {
      insert_urls_paths()
      in_derp = 0
      print
      next
    }
    in_derp == 1 {
      if (skip_paths == 1) {
        if ($0 ~ /^[[:space:]]{4}/) next
        skip_paths = 0
      }
      if (skip_urls == 1) {
        if ($0 ~ /^[[:space:]]{4}/) next
        skip_urls = 0
      }

      if ($0 ~ /^[[:space:]]{2}paths:/) {
        skip_paths = 1
        next
      }

      if (force == 1 && $0 ~ /^[[:space:]]{2}urls:/) {
        skip_urls = 1
        next
      }

      if ($0 ~ /^[[:space:]]{2}auto_update_enabled:/) {
        insert_urls_paths()
        if (force == 1) {
          print "  auto_update_enabled: false"
          next
        }
      }
    }
    { print }
    END {
      if (in_derp == 1) {
        insert_urls_paths()
      }
    }
  ' "$config_path" >"$tmp" || return 1

  mv "$tmp" "$config_path" || return 1
  return 0
}

derper_p_inject_headscale() {
  _derper_require_tty || return $?
  load_system_config || true

  local root_domain="$1" derp_port="$2" region_id="$3" region_name="$4" force_only="${5:-0}"
  local public_ipv4="" public_ipv6=""
  local config_path
  config_path="$(_derper_headscale_config_path)"

  if [ ! -f "$config_path" ]; then
    tgdb_warn "找不到 Headscale 設定檔：$config_path"
    tgdb_warn "已略過注入（請先部署 Headscale）。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  public_ipv4="$(_derper_detect_public_ipv4 2>/dev/null || true)"
  public_ipv6="$(_derper_detect_public_ipv6 2>/dev/null || true)"

  if _derper_is_ipv4_addr "$public_ipv4"; then
    echo "ℹ️ 偵測到公網 IPv4：$public_ipv4"
  else
    tgdb_warn "未能自動偵測公網 IPv4，將保留既有設定值。"
    public_ipv4=""
  fi
  if _derper_is_ipv6_addr "$public_ipv6"; then
    echo "ℹ️ 偵測到公網 IPv6：$public_ipv6"
  else
    tgdb_warn "未能自動偵測公網 IPv6，將保留既有設定值。"
    public_ipv6=""
  fi

  _derper_upsert_derpmap_yaml "$root_domain" "$derp_port" "$region_id" "$region_name" "$public_ipv4" "$public_ipv6" || { ui_pause "按任意鍵返回..."; return 1; }

  if _derper_patch_headscale_config_derp "$config_path" "$force_only"; then
    echo "✅ 已更新：$config_path（已同步修正 derp.paths）"
    if [ "$force_only" -eq 1 ]; then
      echo "✅ 已套用：強制只使用自建 DERP（urls: []、auto_update_enabled: false）"
    fi
  else
    tgdb_err "更新 Headscale config.yaml 失敗：$config_path"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  # 嘗試重啟 headscale 讓設定生效（失敗也不阻斷）
  _systemctl_user_try restart --no-block -- \
    "pod-headscale.service" \
    "container-headscale.service" \
    "headscale-headplane.service" \
    "container-headscale-headplane.service" \
    "container-headscale-postgres.service" \
    "headscale.service" \
    "container-headscale.service" || true

  ui_pause "按任意鍵返回..."
  return 0
}

derper_p_deploy() {
  _derper_require_tty || return $?
  _derper_require_podman_for_quadlet || { ui_pause "按任意鍵返回..."; return 1; }

  load_system_config || true
  create_tgdb_dir || { ui_pause "按任意鍵返回..."; return 1; }

  local root_domain=""
  _derper_prompt_root_domain root_domain || {
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 1
  }

  local region_id="" region_name=""
  _derper_prompt_region_id region_id "$DERPER_DEFAULT_REGION_ID" || {
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 1
  }
  _derper_prompt_region_name region_name "$DERPER_DEFAULT_REGION_NAME" || {
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 1
  }

  local derp_port=""
  if ! derp_port="$(prompt_port_number "DERP 對外 TCP 埠（對外會映射到容器內 443/TLS）" "$DERPER_DEFAULT_PORT")"; then
    local status=$?
    if [ "$status" -eq 2 ]; then
      echo "已取消。"
      return 0
    fi
    tgdb_err "取得埠號失敗"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  if _is_port_in_use "$derp_port"; then
    local next
    next="$(get_next_available_port "$derp_port")"
    tgdb_warn "埠號 $derp_port 已被占用，將自動改用：$next"
    derp_port="$next"
  fi

  local fqdn verify_url
  fqdn="derp.${root_domain}"
  verify_url="https://hs.${root_domain}/verify"

  echo "=================================="
  echo "❖ 部署 DERP（derper）❖"
  echo "=================================="
  echo "網域：$fqdn"
  echo "Region：${region_id} / ${region_name}"
  echo "對外：tcp/${derp_port}（TLS）"
  echo "STUN：udp/${DERPER_STUN_PORT}"
  echo "----------------------------------"
  echo "重要提醒："
  echo " - DERP 需要「直連源站」：請關閉 Cloudflare 代理/CDN（橘雲→灰雲 / DNS only）。"
  echo " - 申請憑證需要：DNS 指向本機 + TCP/80 對外可達（Certbot standalone）。"
  echo " - DERP 建議不要置於 NAT / 反向代理 / Load Balancer 後方。"
  echo "----------------------------------"

  local crt key
  crt="$TGDB_DIR/nginx/certs/${fqdn}.crt"
  key="$TGDB_DIR/nginx/certs/${fqdn}.key"

  if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
    tgdb_warn "開始申請 ${fqdn} 憑證（會暫停 nginx 以釋放 80/TCP）..."
    if ! _derper_issue_cert_for_domain_p "$fqdn"; then
      tgdb_err "申請憑證失敗，請確認 DNS/80 埠/防火牆後重試。"
      ui_pause "按任意鍵返回..."
      return 1
    fi
  else
    echo "已沿用憑證：$crt"
  fi

  _derper_write_env "$fqdn" "$verify_url" || { ui_pause "按任意鍵返回..."; return 1; }

  local instance_dir unit_content
  instance_dir="$(_derper_instance_dir)"
  mkdir -p "$instance_dir" 2>/dev/null || true
  unit_content="$(_derper_render_quadlet_unit "$instance_dir" "$derp_port")" || { ui_pause "按任意鍵返回..."; return 1; }
  _install_service_unit_and_enable "derper" "$DERPER_CONTAINER_NAME" "$unit_content" || {
    ui_pause "按任意鍵返回..."
    return 1
  }

  _derper_firewall_maybe_open_ports "$derp_port" || true

  echo "=================================="
  echo "✅ DERP（${DERPER_CONTAINER_NAME}）啟動中"
  echo "網域：$fqdn"
  echo "對外：tcp/${derp_port}（TLS）"
  echo "STUN：udp/${DERPER_STUN_PORT}"
  echo "測試：https://${fqdn}:${derp_port}"
  echo "----------------------------------"

  if ui_confirm_yn "要將自建 DERP 注入 Headscale（derpmap + config.yaml）嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    local force_only=0
    if ui_confirm_yn "要強制只使用自建 DERP（清空 derp.urls，停用 auto_update）嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
      force_only=1
    else
      # 0：取消強制，但不取消注入
      force_only=0
    fi
    if _derper_headscale_is_local_server; then
      derper_p_inject_headscale "$root_domain" "$derp_port" "$region_id" "$region_name" "$force_only" || true
    else
      _derper_print_headscale_missing_tips
      ui_pause "按任意鍵返回..."
    fi
    return 0
  else
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 0
  fi
}

derper_p_full_remove_integrated() {
  # 供 Headscale 完整移除流程呼叫：不做多餘互動與 pause。
  load_system_config || true

  local fqdn=""
  fqdn="$(_derper_detect_fqdn_from_env 2>/dev/null || true)"
  if [ -z "${fqdn:-}" ]; then
    local root_domain=""
    root_domain="$(_derper_detect_root_domain_from_headscale_config 2>/dev/null || true)"
    if [ -n "${root_domain:-}" ]; then
      fqdn="derp.${root_domain}"
    fi
  fi

  local instance_dir
  instance_dir="$(_derper_instance_dir)"

  _systemctl_user_try disable --now -- "${DERPER_CONTAINER_NAME}.container" "container-${DERPER_CONTAINER_NAME}.service" "${DERPER_CONTAINER_NAME}.service" || true
  _systemctl_user_try stop -- "${DERPER_CONTAINER_NAME}.container" "container-${DERPER_CONTAINER_NAME}.service" "${DERPER_CONTAINER_NAME}.service" || true

  local unit_path
  unit_path="$(_derper_resolved_unit_path 2>/dev/null || true)"
  if [ -n "${unit_path:-}" ] && [ -f "$unit_path" ]; then
    rm -f "$unit_path" 2>/dev/null || true
  fi
  local legacy_path=""
  legacy_path="$(rm_legacy_quadlet_unit_path_by_mode "${DERPER_CONTAINER_NAME}.container" rootless 2>/dev/null || true)"
  if [ -n "${legacy_path:-}" ] && [ "$legacy_path" != "$unit_path" ] && [ -f "$legacy_path" ]; then
    rm -f "$legacy_path" 2>/dev/null || true
  fi
  _systemctl_user_try daemon-reload || true

  if command -v podman >/dev/null 2>&1; then
    podman rm -f "$DERPER_CONTAINER_NAME" 2>/dev/null || true
  fi

  if command -v podman >/dev/null 2>&1; then
    podman unshare rm -rf "$instance_dir" 2>/dev/null || true
  else
    rm -rf "$instance_dir" 2>/dev/null || true
  fi
  echo "✅ 已移除 DERP（derper）：${DERPER_CONTAINER_NAME}（並刪除目錄：$instance_dir）"

  if [ -n "${fqdn:-}" ]; then
    _derper_remove_domain_cert_data "$fqdn" || true
  else
    tgdb_warn "無法推導 DERP FQDN，已略過憑證資料清理。"
  fi
  return 0
}

derper_p_full_remove() {
  _derper_require_tty || return $?
  load_system_config || true

  local instance_dir
  instance_dir="$(_derper_instance_dir)"

  echo "=================================="
  echo "❖ DERP：移除 derper ❖"
  echo "=================================="
  echo "此操作會："
  echo "1) 停止/停用 DERP 容器單元"
  echo "2) 移除 Quadlet 單元檔"
  echo "3) 刪除持久化目錄：$instance_dir"
  echo "4) 嘗試清理 derp.<root_domain> 憑證資料"
  echo "----------------------------------"

  if ! ui_confirm_yn "確定要移除 DERP（derper）嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 0
  fi

  derper_p_full_remove_integrated || true
  ui_pause "按任意鍵返回..."
  return 0
}

derper_p_inject_headscale_detected() {
  _derper_require_tty || return $?
  load_system_config || true

  if ! _derper_headscale_is_local_server; then
    _derper_print_headscale_missing_tips
    ui_pause "按任意鍵返回..."
    return 0
  fi

  local root_domain=""
  _derper_prompt_root_domain root_domain || { [ "$?" -eq 2 ] && return 0; ui_pause "按任意鍵返回..."; return 1; }

  local region_id="" region_name=""
  _derper_prompt_region_id region_id "$DERPER_DEFAULT_REGION_ID" || { [ "$?" -eq 2 ] && return 0; ui_pause "按任意鍵返回..."; return 1; }
  _derper_prompt_region_name region_name "$DERPER_DEFAULT_REGION_NAME" || { [ "$?" -eq 2 ] && return 0; ui_pause "按任意鍵返回..."; return 1; }

  local derp_port=""
  if ! derp_port="$(prompt_port_number "DERP 對外 TCP 埠" "$DERPER_DEFAULT_PORT")"; then
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local force_only=0
  if ui_confirm_yn "要強制只使用自建 DERP（清空 derp.urls，停用 auto_update）嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
    force_only=1
  else
    force_only=0
  fi

  derper_p_inject_headscale "$root_domain" "$derp_port" "$region_id" "$region_name" "$force_only" || true
  return 0
}
