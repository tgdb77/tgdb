tailscale_p_menu() {
  _tailscale_p_require_tty || return $?
  _tailscale_p_require_sudo || { ui_pause "按任意鍵返回..."; return 1; }

  while true; do
    clear
    echo "=================================="
    echo "❖ Tailscale 管理 ❖"
    echo "=================================="
    _tailscale_p_print_status_summary
    echo "1. 安裝/更新 tailscale 客戶端"
    echo "2. 加入 Headscale 伺服器"
    echo "3. Tailnet 服務埠轉發"
    echo "4. 切換 tailscale(up/down）"
    echo "5. 出口節點管理"
    echo "6. SSH 管理"
    echo "7. Taildrive 檔案同步"
    echo "----------------------------------"
    echo "d. 移除/清理 Tailscale"
    echo "----------------------------------"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-7/d]: " choice

    case "$choice" in
      1) tailscale_p_install_client || true ;;
      2) tailscale_p_join_headscale_server || true ;;
      3) tailscale_p_tailnet_port_forward || true ;;
      4) tailscale_p_client_toggle || true ;;
      5) tailscale_p_exit_node_menu || true ;;
      6) tailscale_p_ssh_menu || true ;;
      7) tailscale_p_drive_menu || true ;;
      d|D) tailscale_p_cleanup_action || true ;;
      0) return 0 ;;
      *) tgdb_err "無效選項"; ui_pause "按任意鍵返回..." ;;
    esac
  done
}

_tailscale_p_current_state() {
  if ! command -v tailscale >/dev/null 2>&1; then
    printf '%s\n' "not-installed"
    return 0
  fi

  local out="" backend_state=""
  out="$(_tailscale_p_sudo tailscale status --json 2>&1 || true)"
  if [ -z "${out:-}" ]; then
    printf '%s\n' "unknown"
    return 0
  fi

  if printf '%s\n' "$out" | grep -qiE "Access denied|checkprefs access denied|permission denied"; then
    printf '%s\n' "unknown"
    return 0
  fi

  backend_state="$(printf '%s\n' "$out" | sed -nE 's/.*"BackendState"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1)"
  case "$backend_state" in
    Running)
      printf '%s\n' "up"
      return 0
      ;;
    Starting|NeedsLogin|NeedsMachineAuth|Stopped|NoState)
      printf '%s\n' "down"
      return 0
      ;;
  esac

  if printf '%s\n' "$out" | grep -qiE "failed to connect to local tailscaled|tailscaled.*not.*running|no such file or directory|cannot connect|connection refused|Tailscale is stopped|Logged out|needs login|login required|not authenticated|unauthorized"; then
    printf '%s\n' "down"
    return 0
  fi

  printf '%s\n' "up"
  return 0
}

tailscale_p_client_toggle() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  if ! command -v tailscale >/dev/null 2>&1; then
    tgdb_err "尚未安裝 tailscale，請先執行「安裝/更新 tailscale 客戶端」。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  require_root || { ui_pause "按任意鍵返回..."; return 1; }

  local state=""
  state="$(_tailscale_p_current_state)"

  case "$state" in
    up)
      tailscale_p_client_disable
      ;;
    *)
      tailscale_p_client_enable
      ;;
  esac
}

tailscale_p_client_enable() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  if ! command -v tailscale >/dev/null 2>&1; then
    tgdb_err "尚未安裝 tailscale，請先執行「安裝/更新 tailscale 客戶端」。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  require_root || { ui_pause "按任意鍵返回..."; return 1; }

  # 優先確保 tailscaled 已啟動，避免 tailscale up 找不到 daemon。
  if command -v systemctl >/dev/null 2>&1; then
    _tailscale_p_sudo systemctl start tailscaled 2>/dev/null || true
  fi

  echo "=================================="
  echo "❖ tailscale up（開啟/連線）❖"
  echo "=================================="
  echo "將執行：tailscale up（不帶參數：僅把網路帶回 online，不變更設定）"
  echo "----------------------------------"
  local out rc
  out="$(_tailscale_p_sudo tailscale up 2>&1)" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    tgdb_warn "tailscale up 失敗（rc=$rc）。"
    printf '%s\n' "$out"
    echo "----------------------------------"
    if printf '%s\n' "$out" | grep -Fq "requires mentioning all non-default flags" 2>/dev/null; then
      # 理論上不帶 flags 不會觸發此錯誤；若仍觸發，照建議命令重跑即可。
      _tailscale_p_rerun_up_with_suggested_settings "$out" "" "" 2>&1 || true
      echo "----------------------------------"
    fi
    if printf '%s\n' "$out" | grep -qiE "Logged out|needs login|login required|not authenticated|unauthorized"; then
      tgdb_warn "偵測到目前可能尚未登入/授權。"
      if ui_confirm_yn "是否改用「加入 Headscale（tailscale up --login-server --auth-key）」流程？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        tailscale_p_join_headscale_server || true
        return 0
      fi
    fi
  fi
  ui_pause "完成，按任意鍵返回..."
  return 0
}

tailscale_p_client_disable() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  if ! command -v tailscale >/dev/null 2>&1 && ! command -v tailscaled >/dev/null 2>&1; then
    tgdb_err "尚未偵測到 tailscale/tailscaled。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  require_root || { ui_pause "按任意鍵返回..."; return 1; }

  echo "=================================="
  echo "❖ tailscale down（關閉/斷線）❖"
  echo "=================================="
  echo "----------------------------------"
  _tailscale_p_sudo tailscale down 2>&1 || true

  ui_pause "完成，按任意鍵返回..."
  return 0
}

tailscale_p_cleanup_action() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  clear
  echo "=================================="
  echo "❖ Tailscale：移除/清理 ❖"
  echo "=================================="
  echo "此操作會嘗試："
  echo "1) tailscale down / logout"
  echo "2) 停用 tailscaled"
  echo "3) 若偵測為 TGDB 安裝，則嘗試卸載套件"
  echo "----------------------------------"

  if ! command -v tailscale >/dev/null 2>&1 && ! command -v tailscaled >/dev/null 2>&1; then
    tgdb_warn "未偵測到 tailscale/tailscaled，目前狀態為未安裝。"
    ui_pause "按任意鍵返回..."
    return 0
  fi

  if ! ui_confirm_yn "確定要移除/清理 Tailscale 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 0
  fi

  local managed=0
  if _tailscale_p_installed_by_tgdb || _tailscale_p_joined_by_tgdb; then
    managed=1
  fi

  tailscale_p_cleanup_if_needed || true

  if [ "$managed" -eq 1 ]; then
    echo "✅ 已完成 Tailscale 移除/清理。"
  else
    tgdb_warn "未偵測到 TGDB 安裝/加入標記；已略過自動卸載。若需完全移除，請再用系統套件管理器手動卸載。"
  fi

  ui_pause "按任意鍵返回..."
  return 0
}

tailscale_p_cleanup_if_needed() {
  # 目標：
  # - 完整移除時：嘗試退出並停用 tailscaled
  # - 是否卸載套件：僅在偵測到「由 TGDB 安裝」marker 時才嘗試卸載，避免影響使用者原本用途

  if ! command -v tailscale >/dev/null 2>&1 && ! command -v tailscaled >/dev/null 2>&1; then
    return 0
  fi

  if ! _tailscale_p_installed_by_tgdb && ! _tailscale_p_joined_by_tgdb; then
    return 0
  fi

  tgdb_warn "偵測到 tailscale/tailscaled，將嘗試退出並停用 tailscaled..."

  if ! require_root; then
    tgdb_warn "缺少 root/sudo 權限，已略過 tailscaled 停用/卸載。"
    return 0
  fi

  _tailscale_p_sudo tailscale down 2>/dev/null || true
  _tailscale_p_sudo tailscale logout 2>/dev/null || true

  if _tailscale_p_installed_by_tgdb; then
    if command -v systemctl >/dev/null 2>&1; then
      _tailscale_p_sudo systemctl disable --now tailscaled 2>/dev/null || true
    fi
    tgdb_warn "偵測到 tailscale 由 TGDB 安裝，將嘗試移除套件：tailscale"
    pkg_purge tailscale 2>/dev/null || true
    pkg_autoremove 2>/dev/null || true
    local marker
    marker="$(_tailscale_p_marker_installed_path)"
    if [ -n "${marker:-}" ]; then
      rm -f "$marker" 2>/dev/null || true
    fi
  fi

  if _tailscale_p_joined_by_tgdb; then
    local join_marker
    join_marker="$(_tailscale_p_marker_joined_path)"
    if [ -n "${join_marker:-}" ]; then
      rm -f "$join_marker" 2>/dev/null || true
    fi
  fi

  return 0
}
