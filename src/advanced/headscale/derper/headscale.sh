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

