#!/bin/bash

# Tailscale（客戶端 / Tailnet 相關）管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"

_tailscale_p_require_tty() {
  if ! ui_is_interactive; then
    tgdb_fail "Tailscale 操作需要互動式終端（TTY）。" 2 || true
    return 2
  fi
  return 0
}

_tailscale_p_prompt_server_url_required() {
  local out_var="$1"
  local value=""
  while true; do
    read -r -e -p "請輸入 Headscale URL（login-server，例如：https://hs.example.com，輸入 0 取消）: " value
    if [ "$value" = "0" ]; then
      return 2
    fi
    case "$value" in
      http://*|https://*)
        printf -v "$out_var" '%s' "$value"
        return 0
        ;;
    esac
    tgdb_err "URL 格式不正確，請以 http:// 或 https:// 開頭。"
  done
}

_tailscale_p_prompt_authkey_required() {
  local out_var="$1"
  local value=""
  while true; do
    read -r -s -p "請輸入 Headscale UI 取得的認證 Key（PreAuthKey/AuthKey，輸入 0 取消）: " value
    echo
    if [ "$value" = "0" ]; then
      return 2
    fi
    if [ -z "${value:-}" ]; then
      tgdb_err "認證 Key 不可為空。"
      continue
    fi
    if printf '%s' "$value" | grep -q '[[:space:]]' 2>/dev/null; then
      tgdb_err "認證 Key 不可包含空白。"
      continue
    fi
    printf -v "$out_var" '%s' "$value"
    return 0
  done
}

_tailscale_p_marker_installed_path() {
  # 沿用既有 Headscale 模組的 marker 路徑，避免破壞既有狀態判斷。
  local base
  base="$(rm_persist_config_dir 2>/dev/null || true)"
  [ -n "$base" ] || { echo ""; return 0; }
  printf '%s\n' "$base/headscale/tailscale_installed_by_tgdb"
}

_tailscale_p_marker_joined_path() {
  local base
  base="$(rm_persist_config_dir 2>/dev/null || true)"
  [ -n "$base" ] || { echo ""; return 0; }
  printf '%s\n' "$base/headscale/tailscale_joined_by_tgdb"
}

_tailscale_p_mark_installed() {
  command -v tailscale >/dev/null 2>&1 || return 1
  local marker
  marker="$(_tailscale_p_marker_installed_path)"
  [ -n "${marker:-}" ] || return 1
  mkdir -p "$(dirname "$marker")" 2>/dev/null || true
  touch "$marker" 2>/dev/null || true
  return 0
}

_tailscale_p_mark_joined() {
  command -v tailscale >/dev/null 2>&1 || return 1
  local marker
  marker="$(_tailscale_p_marker_joined_path)"
  [ -n "${marker:-}" ] || return 1
  mkdir -p "$(dirname "$marker")" 2>/dev/null || true
  touch "$marker" 2>/dev/null || true
  return 0
}

_tailscale_p_installed_by_tgdb() {
  local marker
  marker="$(_tailscale_p_marker_installed_path)"
  [ -n "${marker:-}" ] && [ -f "$marker" ]
}

_tailscale_p_joined_by_tgdb() {
  local marker
  marker="$(_tailscale_p_marker_joined_path)"
  [ -n "${marker:-}" ] && [ -f "$marker" ]
}

_tailscale_p_sudo() {
  if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
    "$@"
  else
    sudo "$@"
  fi
}

_tailscale_p_extract_suggested_up_line() {
  # tailscale up 在「缺少非預設參數」時會輸出建議命令，例如：
  #   tailscale up --login-server=... --operator=...
  # 這裡只擷取第一條建議命令行（去掉前導空白）。
  local out="${1:-}"
  printf '%s\n' "$out" | sed -n 's/^[[:space:]]*\(tailscale up .*\)$/\1/p' | head -n 1
}

_tailscale_p_rerun_up_with_suggested_settings() {
  # 依 tailscale 的建議命令重新執行 tailscale up，但允許替換 login-server 並附加 auth-key。
  local out="${1:-}"
  local desired_login_server="${2:-}"
  local authkey="${3:-}"

  local line
  line="$(_tailscale_p_extract_suggested_up_line "$out")"
  [ -n "${line:-}" ] || return 1

  local -a parts=()
  # shellcheck disable=SC2206
  parts=($line)
  [ "${#parts[@]}" -ge 2 ] || return 1
  [ "${parts[0]}" = "tailscale" ] || return 1
  [ "${parts[1]}" = "up" ] || return 1

  local -a cmd=(tailscale up)

  local i=2
  while [ "$i" -lt "${#parts[@]}" ]; do
    local a="${parts[$i]}"

    case "$a" in
      --login-server=*)
        if [ -n "${desired_login_server:-}" ]; then
          cmd+=("--login-server=${desired_login_server}")
        else
          cmd+=("$a")
        fi
        ;;
      --login-server)
        # 罕見：兩段式參數
        if [ -n "${desired_login_server:-}" ]; then
          cmd+=("--login-server=${desired_login_server}")
          i=$((i + 1))
        else
          cmd+=("$a")
          i=$((i + 1))
          [ "$i" -lt "${#parts[@]}" ] && cmd+=("${parts[$i]}")
        fi
        ;;
      --auth-key|--auth-key=*)
        # 由外部附加，避免重複
        ;;
      *)
        cmd+=("$a")
        ;;
    esac

    i=$((i + 1))
  done

  if [ -n "${authkey:-}" ]; then
    cmd+=("--auth-key" "$authkey")
  fi

  _tailscale_p_sudo "${cmd[@]}"
}

tailscale_p_show_status() {
  _tailscale_p_require_tty || return $?
  load_system_config || true

  if ! command -v tailscale >/dev/null 2>&1; then
    tgdb_err "尚未安裝 tailscale。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  require_root || { ui_pause "按任意鍵返回..."; return 1; }

  if command -v systemctl >/dev/null 2>&1; then
    _tailscale_p_sudo systemctl start tailscaled 2>/dev/null || true
  fi

  clear
  echo "=================================="
  echo "❖ tailscale status ❖"
  echo "=================================="
  local st
  st="$(_tailscale_p_sudo tailscale status 2>&1 || true)"
  printf '%s\n' "$st"

  echo "----------------------------------"
  ui_pause "完成，按任意鍵返回..."
  return 0
}

_tailscale_p_install_official_script() {
  # 需要系統層級安裝：使用 sudo/root
  require_root || return 1

  if ! command -v curl >/dev/null 2>&1; then
    tgdb_warn "未偵測到 curl，將先嘗試安裝 curl..."
    install_package curl || return 1
  fi

  echo "=================================="
  echo "❖ 安裝/更新 tailscale（官方腳本）❖"
  echo "=================================="
  echo "警語：此操作會執行 pipe-to-shell：curl ... | sh"
  echo "建議：先於測試環境驗證，並確認你信任 Tailscale 官方來源。"
  echo "----------------------------------"
  echo "將執行：curl -fsSL https://tailscale.com/install.sh | sh"
  echo "----------------------------------"
  ui_confirm_yn "確定要繼續嗎？(y/N，預設 Y，輸入 0 取消): " "Y" || return $?

  if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
  else
    curl -fsSL https://tailscale.com/install.sh | sudo sh
  fi

  if command -v systemctl >/dev/null 2>&1; then
    _tailscale_p_sudo systemctl enable --now tailscaled 2>/dev/null || true
  fi

  if [ -S /var/run/tailscale/tailscaled.sock ]; then
    echo "✅ tailscaled socket 已存在：/var/run/tailscale/tailscaled.sock"
  else
    tgdb_warn "尚未偵測到 tailscaled.sock：/var/run/tailscale/tailscaled.sock"
    tgdb_warn "請確認 tailscaled 是否已啟動（systemctl status tailscaled）"
  fi

  return 0
}

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
  ui_confirm_yn "確定要繼續嗎？(y/N，預設 Y，輸入 0 取消): " "Y" || { ui_pause "按任意鍵返回..."; return 0; }

  echo "----------------------------------"
  _tailscale_p_sudo tailscale down 2>&1 || true

  ui_pause "完成，按任意鍵返回..."
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

tailscale_p_login_label() {
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "❌ 未安裝"
    return 0
  fi

  # tailscale status 在部分環境會需要 sudo/operator 權限；避免在選單中造成中斷，統一吞掉錯誤並提示。
  local out
  out="$(tailscale status 2>&1 || true)"
  if [ -z "${out:-}" ]; then
    echo "未知"
    return 0
  fi

  if printf '%s\n' "$out" | grep -qi "Logged out"; then
    echo "⏸ 未登入"
    return 0
  fi

  if printf '%s\n' "$out" | grep -qiE "Access denied|checkprefs access denied|permission denied|needs login"; then
    echo "⚠️ 需要 sudo/授權"
    return 0
  fi

  echo "✅ 已登入"
  return 0
}
