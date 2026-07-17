_tailscale_p_supports_ssh() {
  command -v tailscale >/dev/null 2>&1 || return 1
  tailscale set --help 2>&1 | grep -q -- '--ssh'
}

tailscale_p_enable_ssh() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  _tailscale_p_require_client_ready || { ui_pause "按任意鍵返回..."; return 1; }

  if ! _tailscale_p_supports_ssh; then
    tgdb_err "目前 tailscale 版本不支援 Tailscale SSH，請先更新 tailscale 客戶端。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  clear
  echo "=================================="
  echo "❖ 啟用 Tailscale SSH ❖"
  echo "=================================="
  echo "此操作會執行：tailscale set --ssh"
  echo "提醒：連線權限仍需由 Headscale/Tailscale ACL policy 允許。"
  echo "建議：到 Headplane 的 ACL 頁面設定 ssh 規則後再測試連線。"
  echo "----------------------------------"
  ui_confirm_yn "確定要啟用 Tailscale SSH 嗎？(y/N，預設 Y，輸入 0 取消): " "Y" || {
    [ "$?" -eq 2 ] && return 0
    return 0
  }

  _tailscale_p_sudo tailscale set --ssh 2>&1 || {
    tgdb_err "啟用 Tailscale SSH 失敗。"
    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "✅ 已啟用 Tailscale SSH。"
  ui_pause "完成，按任意鍵返回..."
  return 0
}

tailscale_p_disable_ssh() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  _tailscale_p_require_client_ready || { ui_pause "按任意鍵返回..."; return 1; }

  if ! _tailscale_p_supports_ssh; then
    tgdb_err "目前 tailscale 版本不支援 Tailscale SSH，請先更新 tailscale 客戶端。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  clear
  echo "=================================="
  echo "❖ 停用 Tailscale SSH ❖"
  echo "=================================="
  echo "將執行：tailscale set --ssh=false"
  echo "----------------------------------"
  ui_confirm_yn "確定要停用 Tailscale SSH 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y" || {
    [ "$?" -eq 2 ] && return 0
    return 0
  }

  _tailscale_p_sudo tailscale set --ssh=false 2>&1 || {
    tgdb_err "停用 Tailscale SSH 失敗。"
    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "✅ 已停用 Tailscale SSH。"
  ui_pause "完成，按任意鍵返回..."
  return 0
}

_tailscale_p_print_ssh_state() {
  echo "❖ SSH 狀態 ❖"

  if ! command -v tailscale >/dev/null 2>&1; then
    echo "tailscale：尚未安裝"
    echo "----------------------------------"
    return 0
  fi

  local prefs="" run_ssh=""
  prefs="$(_tailscale_p_debug_prefs_json || true)"
  run_ssh="$(_tailscale_p_prefs_json_value "$prefs" "RunSSH" || true)"

  echo "本機 Tailscale SSH：$(_tailscale_p_bool_label "$run_ssh")"
  echo "----------------------------------"
}

tailscale_p_ssh_menu() {
  _tailscale_p_require_tty || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ Tailscale SSH ❖"
    echo "=================================="
    _tailscale_p_print_ssh_state
    echo " 使用方式： ssh 用戶名@目標 IP 連接，輸入 exit 退出。"
    echo "=================================="
    echo "1. 啟用本機 Tailscale SSH"
    echo "2. 停用本機 Tailscale SSH"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-2]: " choice

    case "$choice" in
      1) tailscale_p_enable_ssh || true ;;
      2) tailscale_p_disable_ssh || true ;;
      0) return 0 ;;
      *) tgdb_err "無效選項"; ui_pause "按任意鍵返回..." ;;
    esac
  done
}

