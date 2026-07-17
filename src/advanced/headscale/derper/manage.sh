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

derper_p_update_main_program() {
  _derper_require_tty || return $?
  _derper_require_podman_for_quadlet || { ui_pause "按任意鍵返回..."; return 1; }

  load_system_config || true

  if ! _derper_is_installed; then
    tgdb_fail "尚未部署 DERP（derper），請先執行部署。" 1 || true
    ui_pause "按任意鍵返回..."
    return 0
  fi

  echo "=================================="
  echo "❖ DERP 主程式更新 ❖"
  echo "=================================="
  echo "此功能會將已部署的 derper Quadlet 映像改為：$DERPER_IMAGE_LATEST"
  echo "並拉取最新映像、重載 systemd、重啟 derper 容器。"
  echo "----------------------------------"
  tgdb_warn "Tailscale 官方沒有提供 derper 容器自我更新流程；derper 需由部署端自行 build/deploy/update。若使用 verify-clients，請確保驗證端點與 derper 相容後再更新。"
  echo "----------------------------------"

  if ! ui_confirm_yn "確定要更新 DERP 主程式嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "操作已取消。"
    fi
    ui_pause "按任意鍵返回..."
    return 0
  fi

  local unit_path
  unit_path="$(_derper_resolved_unit_path 2>/dev/null || true)"
  if [ -z "$unit_path" ] || [ ! -f "$unit_path" ]; then
    tgdb_fail "找不到 DERP Quadlet 單元：$unit_path" 1 || true
    ui_pause "按任意鍵返回..."
    return 0
  fi

  echo "⏳ 正在更新 Quadlet 映像設定..."
  _derper_update_unit_image_to_latest "$unit_path" || {
    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "⏳ 正在拉取最新 derper 映像..."
  if ! tgdb_podman pull "$DERPER_IMAGE_LATEST"; then
    tgdb_fail "拉取 derper 映像失敗，請檢查網路或 registry 狀態。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "⏳ 正在重載 systemd 並重啟 derper..."
  _systemctl_user_try daemon-reload >/dev/null 2>&1 || true
  if ! _systemctl_user_try restart -- "${DERPER_CONTAINER_NAME}.container" "${DERPER_CONTAINER_NAME}.service" "container-${DERPER_CONTAINER_NAME}.service"; then
    tgdb_fail "重啟 derper 失敗，請檢查 systemd 與 Podman 日誌。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "🧹 更新成功，正在清理無標籤的舊映像..."
  tgdb_podman image prune -f || tgdb_warn "舊映像清理失敗，請稍後從 Podman 管理選單重試。"
  echo "✅ DERP 主程式已更新。"
  ui_pause "按任意鍵返回..."
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
