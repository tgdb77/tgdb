tailscale_p_install_client() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  local was_installed=0
  if command -v tailscale >/dev/null 2>&1; then
    was_installed=1
  fi

  _tailscale_p_install_official_script || { ui_pause "按任意鍵返回..."; return 1; }

  if [ "$was_installed" -eq 0 ]; then
    _tailscale_p_mark_installed || true
  fi

  ui_pause "完成，按任意鍵返回..."
  return 0
}

tailscale_p_join_headscale_server() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  if ! command -v tailscale >/dev/null 2>&1; then
    tgdb_err "尚未安裝 tailscale，請先執行「安裝/更新 tailscale」。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    _tailscale_p_sudo systemctl start tailscaled 2>/dev/null || true
  fi

  local server_url=""
  _tailscale_p_prompt_server_url_required server_url || {
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 1
  }

  local authkey=""
  _tailscale_p_prompt_authkey_required authkey || {
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "=================================="
  echo "❖ tailscale up（加入 Headscale）❖"
  echo "=================================="
  echo "login-server：$server_url"
  echo "----------------------------------"
  echo "提醒：若你使用 Cloudflare 代理/CDN（橘雲），可能導致註冊/認證失敗。"
  echo "建議：加入前先關閉代理（DNS only / 灰雲），讓客戶端可直連源站 IP。"
  echo "----------------------------------"

  # tailscale up 需要 root 權限（寫入路由/介面）
  require_root || { ui_pause "按任意鍵返回..."; return 1; }

  local out rc
  out="$(_tailscale_p_sudo tailscale up --login-server "$server_url" --auth-key "$authkey" 2>&1)" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    _tailscale_p_mark_joined || true
  else
    # tailscale：只要這次 tailscale up 帶了任何「設定類 flags」，就要求把所有非預設設定都帶上。
    # 若使用者之前已設定 operator/login-server 等，這裡不補齊就會被拒絕。
    if printf '%s\n' "$out" | grep -Fq "requires mentioning all non-default flags" 2>/dev/null; then
      if _tailscale_p_rerun_up_with_suggested_settings "$out" "$server_url" "$authkey" >/dev/null 2>&1; then
        _tailscale_p_mark_joined || true
      else
        printf '%s\n' "$out"
        tgdb_err "加入失敗：tailscale 要求補齊所有非預設 flags（請見上方建議命令）。"
      fi
    else
      printf '%s\n' "$out"
      tgdb_err "加入失敗，請確認 server_url 與認證 Key，並確認已關閉 Cloudflare 代理（灰雲）。"
    fi
  fi

  ui_pause "完成，按任意鍵返回..."
  return 0
}

tailscale_p_tailnet_port_forward() {
  _tailscale_p_require_tty || return $?

  # 這個功能實作在 nftables 模組（避免重複造輪子），此處只提供入口。
  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "nftables" || { ui_pause "按任意鍵返回..."; return 1; }
  else
    # shellcheck source=src/nftables.sh
    source "$SRC_ROOT/nftables.sh"
  fi

  if ! declare -F nftables_ts_forward_menu >/dev/null 2>&1; then
    tgdb_fail "找不到 nftables Tailnet 轉發功能（nftables_ts_forward_menu）。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  nftables_ts_forward_menu || true
  return 0
}

