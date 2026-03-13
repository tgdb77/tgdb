#!/bin/bash

# tmux 工作區（session）管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"

_tmux_is_installed() {
  local bin=""
  bin="$(type -P tmux 2>/dev/null || true)"
  [ -n "${bin:-}" ] && [ -x "$bin" ]
}

_tmux_require_tty() {
  if ! ui_is_input_tty; then
    tgdb_fail "此操作需要互動式終端（TTY）。" 2 || true
    return 2
  fi
  return 0
}

_tmux_require_tmux() {
  if _tmux_is_installed; then
    return 0
  fi
  tgdb_fail "尚未安裝 tmux，請先選擇「1. 安裝 tmux」。" 1 || true
  return 1
}

_tmux_is_valid_session_name() {
  local name="${1:-}"
  [ -n "$name" ] || return 1
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]
}

_tmux_list_sessions_raw() {
  _tmux_is_installed || return 0
  tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null || true
}

_tmux_list_session_names() {
  _tmux_list_sessions_raw | cut -d'|' -f1 | awk 'NF>0'
}

_tmux_session_exists() {
  local name="$1"
  _tmux_is_installed || return 1
  tmux has-session -t "$name" 2>/dev/null
}

_tmux_print_sessions_panel() {
  if ! _tmux_is_installed; then
    echo "tmux 狀態：未安裝"
    echo "工作區（session）：（無法列出，請先安裝 tmux）"
    return 0
  fi

  echo "tmux 狀態：已安裝（$(tmux -V 2>/dev/null || echo "tmux" )）"
  echo "工作區（session）列表："

  local -a rows=()
  mapfile -t rows < <(_tmux_list_sessions_raw)

  if [ ${#rows[@]} -eq 0 ]; then
    echo "  （目前沒有任何 session）"
    return 0
  fi

  local i row name windows attached
  for i in "${!rows[@]}"; do
    row="${rows[$i]}"
    IFS='|' read -r name windows attached <<< "$row"
    [ -z "${name:-}" ] && continue
    printf '  %2d) %s（視窗:%s，已附加:%s）\n' "$((i + 1))" "$name" "${windows:-?}" "${attached:-?}"
  done
}

_tmux_select_existing_session() {
  local out_var="$1"
  local prompt="${2:-請輸入工作區編號（輸入 0 取消）: }"

  local -a sessions=()
  mapfile -t sessions < <(_tmux_list_session_names)

  if [ ${#sessions[@]} -eq 0 ]; then
    tgdb_err "目前沒有任何可選擇的 session。"
    return 1
  fi

  local idx
  if ! ui_prompt_index idx "$prompt" 1 "${#sessions[@]}" "" 0; then
    return 2
  fi

  printf -v "$out_var" '%s' "${sessions[$((idx - 1))]}"
  return 0
}

_tmux_install() {
  if _tmux_is_installed; then
    echo "✅ tmux 已安裝，無需重複安裝。"
    return 0
  fi

  require_root || return 1
  echo "正在安裝 tmux..."
  install_package tmux

  if _tmux_is_installed; then
    echo "✅ tmux 安裝完成。"
    return 0
  fi

  tgdb_fail "tmux 安裝失敗（安裝後未偵測到 tmux 指令）。" 1 || true
  return 1
}

_tmux_update() {
  _tmux_require_tmux || return 1
  require_root || return 1

  local before_version after_version
  before_version="$(tmux -V 2>/dev/null || echo "tmux")"

  echo "正在更新 tmux..."
  pkg_update || true
  if ! pkg_install tmux; then
    tgdb_fail "tmux 更新失敗。" 1 || true
    return 1
  fi

  hash -r 2>/dev/null || true

  if ! _tmux_is_installed; then
    tgdb_fail "tmux 更新失敗（更新後未偵測到 tmux 指令）。" 1 || true
    return 1
  fi

  after_version="$(tmux -V 2>/dev/null || echo "tmux")"
  echo "✅ tmux 更新完成：$before_version -> $after_version"

  if [ -n "$(_tmux_list_sessions_raw)" ]; then
    tgdb_warn "偵測到仍有 tmux 工作區在執行；現有 session 可能仍由舊版 tmux server 提供服務。"
    if ui_is_interactive; then
      if ui_confirm_yn "要立即重啟 tmux server 套用新版嗎？這會中斷所有工作區。(y/N，預設 N，輸入 0 取消): " "N"; then
        tmux kill-server >/dev/null 2>&1 || true
        echo "✅ 已重啟 tmux server。"
      else
        local restart_rc=$?
        if [ "$restart_rc" -eq 2 ]; then
          echo "已取消重啟 tmux server。"
        else
          echo "已保留目前 tmux server；下次重新啟動 session 後會使用新版。"
        fi
      fi
    fi
  fi

  return 0
}

_tmux_uninstall() {
  if ! _tmux_is_installed; then
    echo "✅ tmux 未安裝，無需移除。"
    return 0
  fi

  require_root || return 1

  local has_sessions="0"
  if [ -n "$(_tmux_list_sessions_raw)" ]; then
    has_sessions="1"
  fi

  if [ "$has_sessions" = "1" ]; then
    tgdb_warn "偵測到仍有 tmux 工作區在執行。移除前建議先確認是否要結束所有 session。"
    if ui_is_interactive; then
      if ui_confirm_yn "要先關閉所有 tmux 工作區（kill-server）嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        tmux kill-server >/dev/null 2>&1 || true
      else
        echo "已略過 kill-server。"
      fi
    fi
  fi

  echo "正在移除 tmux..."
  pkg_purge tmux || true
  pkg_autoremove || true

  # 避免 bash 的 command hash 造成「已移除但仍誤判存在」的情況
  hash -r 2>/dev/null || true

  if ! _tmux_is_installed; then
    echo "✅ tmux 已移除。"
    return 0
  fi

  local bin=""
  bin="$(type -P tmux 2>/dev/null || true)"
  if [ -n "${bin:-}" ]; then
    tgdb_fail "tmux 移除失敗（仍偵測到 tmux 指令：$bin）。" 1 || true
  else
    tgdb_fail "tmux 移除失敗（仍偵測到 tmux 指令）。" 1 || true
  fi
  return 1
}

_tmux_enter_session() {
  local session="$1"

  _tmux_require_tmux || return 1
  _tmux_require_tty || return $?

  if ! _tmux_is_valid_session_name "$session"; then
    tgdb_fail "session 名稱不合法：$session（只允許英數、.、_、-，且需以英數開頭）" 2 || true
    return 2
  fi

  if _tmux_session_exists "$session"; then
    if [ -n "${TMUX:-}" ]; then
      if ! tmux switch-client -t "$session"; then
        tgdb_fail "切換至 session 失敗：$session" 1 || true
        return 1
      fi
    else
      if ! tmux attach-session -t "$session"; then
        tgdb_fail "進入 session 失敗：$session" 1 || true
        return 1
      fi
    fi
    return 0
  fi

  if [ -n "${TMUX:-}" ]; then
    if ! tmux new-session -d -s "$session"; then
      tgdb_fail "建立 session 失敗：$session" 1 || true
      return 1
    fi
    if ! tmux switch-client -t "$session"; then
      tgdb_fail "已建立 session 但切換失敗：$session" 1 || true
      return 1
    fi
  else
    if ! tmux new-session -s "$session"; then
      tgdb_fail "建立並進入 session 失敗：$session" 1 || true
      return 1
    fi
  fi
}

_tmux_create_and_enter_session() {
  local session="$1"

  _tmux_require_tmux || return 1
  _tmux_require_tty || return $?

  if ! _tmux_is_valid_session_name "$session"; then
    tgdb_fail "session 名稱不合法：$session（只允許英數、.、_、-，且需以英數開頭）" 2 || true
    return 2
  fi

  if _tmux_session_exists "$session"; then
    tgdb_warn "已存在同名 session：$session"
    if ui_confirm_yn "要直接進入既有 session 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      _tmux_enter_session "$session"
      return $?
    fi
    return 2
  fi

  _tmux_enter_session "$session"
}

_tmux_pick_target_pane_id() {
  local session="$1"
  local pane_id=""

  pane_id="$(
    tmux list-panes -t "$session" -F '#{pane_id} #{pane_active}' 2>/dev/null \
      | awk '$2==1{print $1; exit}' \
      || true
  )"

  if [ -z "${pane_id:-}" ]; then
    pane_id="$(
      tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null | head -n 1 || true
    )"
  fi

  [ -n "${pane_id:-}" ] || return 1
  printf '%s\n' "$pane_id"
  return 0
}

_tmux_inject_command() {
  local session="$1"
  local cmd="$2"

  _tmux_require_tmux || return 1
  if ! _tmux_session_exists "$session"; then
    tgdb_fail "找不到 session：$session" 1 || true
    return 1
  fi

  if [ -z "${cmd:-}" ]; then
    tgdb_fail "指令不可為空。" 2 || true
    return 2
  fi

  local pane_id
  pane_id="$(_tmux_pick_target_pane_id "$session")" || {
    tgdb_fail "無法取得 session 的目標 pane（session 可能沒有可用的 pane）。" 1 || true
    return 1
  }

  tmux send-keys -t "$pane_id" -l "$cmd"
  tmux send-keys -t "$pane_id" C-m
  echo "✅ 已注入指令到 $session（pane: $pane_id）。"
}

_tmux_kill_session() {
  local session="$1"

  _tmux_require_tmux || return 1
  if ! _tmux_session_exists "$session"; then
    tgdb_fail "找不到 session：$session" 1 || true
    return 1
  fi
  tmux kill-session -t "$session"
  echo "✅ 已刪除 session：$session"
}

tmux_menu() {
  if ! ui_is_interactive; then
    tgdb_fail "tmux 工作區管理需要互動式終端（TTY）。" 2 || true
    return 2
  fi

  while true; do
    clear
    print_header "tmux 工作區管理"
    echo "教學與文件：https://github.com/tmux/tmux/wiki/Getting-Started"
    echo "提示：離開當前會話不中斷：ctrl+b d"
    echo "----------------------------------"
    _tmux_print_sessions_panel
    echo "----------------------------------"
    echo "1. 安裝 tmux"
    echo "2. 建立並進入工作區（session）"
    echo "3. 進入指定工作區（用編號選擇）"
    echo "4. 注入指令到指定工作區"
    echo "5. 刪除指定工作區"
    echo "6. 更新 tmux"
    echo "----------------------------------"
    echo "d. 移除 tmux"
    echo "----------------------------------"
    echo "0. 返回主選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-6/d]: " choice

    case "$choice" in
      1)
        _tmux_install
        ui_pause "按任意鍵返回..."
        ;;
      2)
        if ! _tmux_require_tmux; then
          ui_pause "按任意鍵返回..."
          continue
        fi
        local session=""
        read -r -e -p "請輸入要建立的工作區名稱（例如 tgdb-dev，輸入 0 取消）: " session
        if [ "$session" = "0" ]; then
          continue
        fi
        if ! _tmux_create_and_enter_session "$session"; then
          ui_pause "按任意鍵返回..."
        fi
        ;;
      3)
        if ! _tmux_require_tmux; then
          ui_pause "按任意鍵返回..."
          continue
        fi
        local session=""
        if _tmux_select_existing_session session; then
          if ! _tmux_enter_session "$session"; then
            ui_pause "按任意鍵返回..."
          fi
        else
          ui_pause "按任意鍵返回..."
        fi
        ;;
      4)
        if ! _tmux_require_tmux; then
          ui_pause "按任意鍵返回..."
          continue
        fi
        local session="" cmd=""
        if ! _tmux_select_existing_session session; then
          ui_pause "按任意鍵返回..."
          continue
        fi
        read -r -e -p "請輸入要注入的指令（輸入 0 取消）: " cmd
        if [ "$cmd" = "0" ]; then
          continue
        fi
        _tmux_inject_command "$session" "$cmd" || true
        ui_pause "按任意鍵返回..."
        ;;
      5)
        if ! _tmux_require_tmux; then
          ui_pause "按任意鍵返回..."
          continue
        fi
        local session=""
        if ! _tmux_select_existing_session session "請輸入要刪除的工作區編號（輸入 0 取消）: "; then
          ui_pause "按任意鍵返回..."
          continue
        fi
        if ui_confirm_yn "確定要刪除 session「$session」嗎？(Y/n，預設 N，輸入 0 取消): " "N"; then
          _tmux_kill_session "$session" || true
        else
          echo "已取消。"
        fi
        ui_pause "按任意鍵返回..."
        ;;
      6)
        _tmux_update
        ui_pause "按任意鍵返回..."
        ;;
      d|D)
        if ui_confirm_yn "確定要移除 tmux 嗎？(Y/n，預設 N，輸入 0 取消): " "N"; then
          _tmux_uninstall || true
        else
          echo "已取消。"
        fi
        ui_pause "按任意鍵返回..."
        ;;
      0)
        break
        ;;
      *)
        echo "無效選項，請重新輸入。"
        sleep 1
        ;;
    esac
  done
}

# ---- CLI wrappers ----

tmux_install_cli() {
  _tmux_install
}

tmux_update_cli() {
  _tmux_update
}

tmux_create_and_enter_cli() {
  local session="${1:-}"
  if [ -z "$session" ] || [ "$session" = "0" ]; then
    session="tgdb"
  fi
  _tmux_enter_session "$session"
}

tmux_enter_existing_cli() {
  local session="${1:-}"
  [ -n "$session" ] || { tgdb_fail "用法：t 7 3 3 <session>" 2 || true; return 2; }
  _tmux_enter_session "$session"
}

tmux_inject_cli() {
  local session="${1:-}"; shift || true
  [ -n "$session" ] || { tgdb_fail "用法：t 7 3 4 <session> <cmd...>" 2 || true; return 2; }
  local cmd="$*"
  _tmux_inject_command "$session" "$cmd"
}

tmux_kill_cli() {
  local session="${1:-}"
  [ -n "$session" ] || { tgdb_fail "用法：t 7 3 5 <session>" 2 || true; return 2; }
  _tmux_kill_session "$session"
}

tmux_uninstall_cli() {
  if [ "$#" -gt 0 ]; then
    tgdb_fail "用法：t 7 3 d" 2 || true
    return 2
  fi
  if _tmux_is_installed; then
    tmux kill-server >/dev/null 2>&1 || true
  fi
  _tmux_uninstall
}
