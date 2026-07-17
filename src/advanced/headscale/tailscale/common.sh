#!/bin/bash

# Tailscale 客戶端／Tailnet 管理模組（Headscale 子模組）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

TAILSCALE_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$TAILSCALE_MODULE_DIR/../../.." && pwd)"

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

_tailscale_p_require_sudo() {
  if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    tgdb_err "Tailscale 管理需要 sudo，但系統未安裝 sudo。"
    return 1
  fi
  if ! sudo -v; then
    tgdb_err "未取得 sudo 權限，已返回。"
    return 1
  fi
  return 0
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

_tailscale_p_print_status_summary() {
  echo "❖ 目前狀態 ❖"

  if ! command -v tailscale >/dev/null 2>&1 && ! command -v tailscaled >/dev/null 2>&1; then
    echo "安裝狀態：未安裝 tailscale"
    echo "連線狀態：不可用"
    echo "----------------------------------"
    return 0
  fi

  if ! command -v tailscale >/dev/null 2>&1; then
    echo "安裝狀態：偵測到 tailscaled，但找不到 tailscale CLI。"
    echo "連線狀態：不可用"
    echo "----------------------------------"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    _tailscale_p_sudo systemctl start tailscaled 2>/dev/null || true
  fi

  local st=""
  st="$(_tailscale_p_sudo tailscale status 2>&1 || true)"
  echo "安裝狀態：已安裝 tailscale"
  if [ -z "${st:-}" ]; then
    echo "無法取得 tailscale 狀態。"
  else
    printf '%s\n' "$st" | sed -n '1,12p'
  fi

  echo "----------------------------------"
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
