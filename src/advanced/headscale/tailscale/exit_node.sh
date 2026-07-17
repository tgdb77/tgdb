_tailscale_p_require_client_ready() {
  if ! command -v tailscale >/dev/null 2>&1; then
    tgdb_err "尚未安裝 tailscale，請先執行「安裝/更新 tailscale 客戶端」。"
    return 1
  fi

  require_root || return 1

  if command -v systemctl >/dev/null 2>&1; then
    _tailscale_p_sudo systemctl start tailscaled 2>/dev/null || true
  fi

  return 0
}

_tailscale_p_debug_prefs_json() {
  command -v tailscale >/dev/null 2>&1 || return 1
  _tailscale_p_sudo tailscale debug prefs 2>/dev/null || return 1
}

_tailscale_p_prefs_json_value() {
  local json="${1:-}"
  local key="${2:-}"
  [ -n "$json" ] && [ -n "$key" ] || return 1

  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$json" | jq -r --arg key "$key" '.[$key] // empty' 2>/dev/null
    return 0
  fi

  printf '%s\n' "$json" | sed -nE 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*"?([^",]+)"?,?[[:space:]]*$/\1/p' | head -n1
}

_tailscale_p_bool_label() {
  case "${1:-}" in
    true) printf '%s\n' "已啟用" ;;
    false) printf '%s\n' "未啟用" ;;
    *) printf '%s\n' "未知" ;;
  esac
}

_tailscale_p_ip_forwarding_sysctl_file() {
  if [ -d /etc/sysctl.d ]; then
    printf '%s\n' "/etc/sysctl.d/99-tailscale.conf"
  else
    printf '%s\n' "/etc/sysctl.conf"
  fi
}

_tailscale_p_enable_ip_forwarding() {
  local sysctl_file
  sysctl_file="$(_tailscale_p_ip_forwarding_sysctl_file)"

  echo "將設定 Linux IP forwarding：$sysctl_file"

  if ! _tailscale_p_sudo grep -Eq '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$sysctl_file" 2>/dev/null; then
    printf '%s\n' 'net.ipv4.ip_forward = 1' | _tailscale_p_sudo tee -a "$sysctl_file" >/dev/null
  fi

  if ! _tailscale_p_sudo grep -Eq '^[[:space:]]*net\.ipv6\.conf\.all\.forwarding[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$sysctl_file" 2>/dev/null; then
    printf '%s\n' 'net.ipv6.conf.all.forwarding = 1' | _tailscale_p_sudo tee -a "$sysctl_file" >/dev/null
  fi

  _tailscale_p_sudo sysctl -p "$sysctl_file" >/dev/null 2>&1 || {
    tgdb_warn "套用 sysctl 失敗，請手動檢查：$sysctl_file"
    return 1
  }

  return 0
}

_tailscale_p_disable_ip_forwarding() {
  local sysctl_file
  sysctl_file="$(_tailscale_p_ip_forwarding_sysctl_file)"

  echo "將關閉 Linux IP forwarding：$sysctl_file"

  if [ -d /etc/sysctl.d ]; then
    {
      printf '%s\n' 'net.ipv4.ip_forward = 0'
      printf '%s\n' 'net.ipv6.conf.all.forwarding = 0'
    } | _tailscale_p_sudo tee "$sysctl_file" >/dev/null
  else
    printf '%s\n' 'net.ipv4.ip_forward = 0' | _tailscale_p_sudo tee -a "$sysctl_file" >/dev/null
    printf '%s\n' 'net.ipv6.conf.all.forwarding = 0' | _tailscale_p_sudo tee -a "$sysctl_file" >/dev/null
  fi

  _tailscale_p_sudo sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
  _tailscale_p_sudo sysctl -w net.ipv6.conf.all.forwarding=0 >/dev/null 2>&1 || true
  _tailscale_p_sudo sysctl -p "$sysctl_file" >/dev/null 2>&1 || {
    tgdb_warn "套用 sysctl 失敗，請手動檢查：$sysctl_file"
    return 1
  }

  return 0
}

tailscale_p_advertise_exit_node() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  _tailscale_p_require_client_ready || { ui_pause "按任意鍵返回..."; return 1; }

  clear
  echo "=================================="
  echo "❖ 宣告本機為 Tailscale 出口節點 ❖"
  echo "=================================="
  echo "此操作會："
  echo "1. 啟用 Linux IPv4/IPv6 forwarding。"
  echo "2. 執行：tailscale set --advertise-exit-node"
  echo "3. 仍需在 Headscale / Tailscale 管理介面允許此節點作為出口節點。"
  echo "----------------------------------"
  ui_confirm_yn "確定要繼續嗎？(y/N，預設 Y，輸入 0 取消): " "Y" || {
    [ "$?" -eq 2 ] && return 0
    return 0
  }

  _tailscale_p_enable_ip_forwarding || true

  echo "----------------------------------"
  _tailscale_p_sudo tailscale set --advertise-exit-node 2>&1 || {
    tgdb_err "宣告出口節點失敗，請確認 tailscale 已登入且 tailscaled 正常運作。"
    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "✅ 已宣告本機為出口節點。"
  tgdb_warn "請到 Headscale / Tailscale 管理介面核准 Use as exit node，其他裝置才可使用。"
  ui_pause "完成，按任意鍵返回..."
  return 0
}

tailscale_p_unadvertise_exit_node() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  _tailscale_p_require_client_ready || { ui_pause "按任意鍵返回..."; return 1; }

  clear
  echo "=================================="
  echo "❖ 停止宣告本機為出口節點 ❖"
  echo "=================================="
  echo "將執行：tailscale set --advertise-exit-node=false"
  echo "並一併關閉 Linux IPv4/IPv6 forwarding。"
  echo "----------------------------------"
  ui_confirm_yn "確定要停止宣告出口節點嗎？(y/N，預設 Y，輸入 0 取消): " "Y" || {
    [ "$?" -eq 2 ] && return 0
    return 0
  }

  _tailscale_p_sudo tailscale set --advertise-exit-node=false 2>&1 || {
    tgdb_err "停止宣告出口節點失敗。"
    ui_pause "按任意鍵返回..."
    return 1
  }

  _tailscale_p_disable_ip_forwarding || true

  echo "✅ 已停止宣告本機為出口節點。"
  ui_pause "完成，按任意鍵返回..."
  return 0
}

tailscale_p_use_exit_node() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  _tailscale_p_require_client_ready || { ui_pause "按任意鍵返回..."; return 1; }

  clear
  echo "=================================="
  echo "❖ 使用 Tailscale 出口節點 ❖"
  echo "=================================="
  if tailscale exit-node list >/dev/null 2>&1; then
    _tailscale_p_sudo tailscale exit-node list 2>&1 || true
    echo "----------------------------------"
  else
    tgdb_warn "目前 tailscale 版本可能不支援 exit-node list，請手動輸入節點名稱或 100.x IP。"
    echo "----------------------------------"
  fi

  local exit_node=""
  read -r -e -p "請輸入出口節點名稱/IP（可填 auto:any，輸入 0 取消）: " exit_node
  if [ "$exit_node" = "0" ]; then
    return 0
  fi
  if [ -z "${exit_node:-}" ]; then
    tgdb_err "出口節點不可為空。"
    ui_pause "按任意鍵返回..."
    return 1
  fi
  if printf '%s' "$exit_node" | grep -q '[[:space:]]' 2>/dev/null; then
    tgdb_err "出口節點名稱/IP 不可包含空白。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "⚠️  強烈建議保留本機 LAN 存取。"
  echo "若關閉 LAN 存取，正在使用的 SSH / 區網連線可能會立刻斷線。"
  echo "除非你明確知道自己正在做什麼，請保持預設 Y。"
  echo "----------------------------------"

  local lan_flag="--exit-node-allow-lan-access=false"
  if ui_confirm_yn "使用出口節點時是否保留本機 LAN 存取？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    lan_flag="--exit-node-allow-lan-access=true"
  else
    [ "$?" -eq 2 ] && return 0
    echo "----------------------------------"
    tgdb_warn "你選擇關閉 LAN 存取，這可能造成目前 SSH 連線斷線。"
    ui_confirm_yn "最後確認：仍要關閉 LAN 存取並繼續嗎？(y/N，預設 N，輸入 0 取消): " "N" || {
      [ "$?" -eq 2 ] && return 0
      return 0
    }
  fi

  echo "----------------------------------"
  _tailscale_p_sudo tailscale set "--exit-node=$exit_node" "$lan_flag" 2>&1 || {
    tgdb_err "設定出口節點失敗，請確認節點已核准為出口節點，且目前帳號/ACL 允許使用。"
    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "✅ 已設定使用出口節點：$exit_node"
  ui_pause "完成，按任意鍵返回..."
  return 0
}

tailscale_p_clear_exit_node() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  _tailscale_p_require_client_ready || { ui_pause "按任意鍵返回..."; return 1; }

  clear
  echo "=================================="
  echo "❖ 停止使用 Tailscale 出口節點 ❖"
  echo "=================================="
  echo "將執行：tailscale set --exit-node="
  echo "----------------------------------"
  ui_confirm_yn "確定要停止使用出口節點嗎？(Y/n，預設 Y，輸入 0 取消): " "Y" || {
    [ "$?" -eq 2 ] && return 0
    return 0
  }

  _tailscale_p_sudo tailscale set --exit-node= 2>&1 || {
    tgdb_err "停止使用出口節點失敗。"
    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "✅ 已停止使用出口節點。"
  ui_pause "完成，按任意鍵返回..."
  return 0
}

_tailscale_p_print_exit_node_state() {
  echo "❖ 出口節點狀態 ❖"

  if ! command -v tailscale >/dev/null 2>&1; then
    echo "tailscale：尚未安裝"
    echo "----------------------------------"
    return 0
  fi

  local prefs="" advertise_routes="" advertise_exit="false"
  local exit_node_id="" exit_node_ip="" lan_access="" status_json="" exit_node_name=""
  prefs="$(_tailscale_p_debug_prefs_json || true)"

  advertise_routes="$(_tailscale_p_prefs_json_value "$prefs" "AdvertiseRoutes" | tr -d '[] "' || true)"
  if printf '%s\n' "$advertise_routes" | grep -Eq '(^|,)0\.0\.0\.0/0(,|$)|(^|,)::/0(,|$)'; then
    advertise_exit="true"
  fi

  exit_node_id="$(_tailscale_p_prefs_json_value "$prefs" "ExitNodeID" || true)"
  exit_node_ip="$(_tailscale_p_prefs_json_value "$prefs" "ExitNodeIP" || true)"
  lan_access="$(_tailscale_p_prefs_json_value "$prefs" "ExitNodeAllowLANAccess" || true)"

  if command -v jq >/dev/null 2>&1; then
    status_json="$(_tailscale_p_sudo tailscale status --json 2>/dev/null || true)"
    if [ -n "${exit_node_id:-}" ] && [ -n "${status_json:-}" ]; then
      exit_node_name="$(printf '%s\n' "$status_json" | jq -r --arg id "$exit_node_id" '.Peer[]? | select(.ID == $id) | (.HostName // .DNSName // .TailscaleIPs[0] // empty)' 2>/dev/null | head -n1)"
    fi
  fi

  echo "本機宣告出口節點：$(_tailscale_p_bool_label "$advertise_exit")"
  if [ -n "${exit_node_id:-}${exit_node_ip:-}" ]; then
    echo "目前使用出口節點：已連接"
    [ -n "${exit_node_name:-}" ] && echo "出口節點名稱：$exit_node_name"
    [ -n "${exit_node_ip:-}" ] && echo "出口節點 IP：$exit_node_ip"
    [ -n "${exit_node_id:-}" ] && echo "出口節點 ID：$exit_node_id"
    [ -n "${lan_access:-}" ] && echo "保留 LAN 存取：$(_tailscale_p_bool_label "$lan_access")"
  else
    echo "目前使用出口節點：未連接"
  fi
  echo "----------------------------------"
}

_tailscale_p_print_available_exit_nodes() {
  echo "❖ 可用出口節點 ❖"
  if ! _tailscale_p_require_client_ready; then
    echo "目前無法取得可用出口節點。"
    echo "----------------------------------"
    return 0
  fi
  _tailscale_p_sudo tailscale exit-node list 2>&1 || true
  echo "----------------------------------"
}

tailscale_p_exit_node_menu() {
  _tailscale_p_require_tty || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ Tailscale 出口節點 ❖"
    echo "=================================="
    _tailscale_p_print_exit_node_state
    _tailscale_p_print_available_exit_nodes
    echo "1. 宣告本機為出口節點"
    echo "2. 停止宣告本機為出口節點"
    echo "3. 本機使用出口節點"
    echo "4. 本機停止使用出口節點"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-4]: " choice

    case "$choice" in
      1) tailscale_p_advertise_exit_node || true ;;
      2) tailscale_p_unadvertise_exit_node || true ;;
      3) tailscale_p_use_exit_node || true ;;
      4) tailscale_p_clear_exit_node || true ;;
      0) return 0 ;;
      *) tgdb_err "無效選項"; ui_pause "按任意鍵返回..." ;;
    esac
  done
}
