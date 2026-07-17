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

# 安全預設：驗證端點不可達時拒絕連線，避免公開 DERP 被陌生客戶端使用
DERP_VERIFY_CLIENT_URL_FAIL_OPEN=false
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

