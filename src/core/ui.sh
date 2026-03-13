#!/bin/bash

# TGDB UI/互動工具（供各模組共用）
# 注意：此檔案為 library，請勿在此更改 shell options（例如 set -e）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_CORE_UI_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_UI_LOADED=1

ui_is_cli_mode() {
  [ "${TGDB_CLI_MODE:-0}" = "1" ]
}

ui_is_input_tty() {
  [ -t 0 ]
}

ui_is_interactive() {
  ui_is_input_tty && ! ui_is_cli_mode
}

_ui_pause_impl() {
  local msg="${1:-按任意鍵返回...}"
  local mode="${2:-interactive}" # interactive|main

  case "$mode" in
    interactive)
      ui_is_interactive || return 0
      ;;
    main)
      if ui_is_cli_mode; then
        echo "$msg (CLI 模式已略過等待)"
        return 0
      fi
      if ! ui_is_input_tty; then
        echo "$msg (非互動終端已略過等待)"
        return 0
      fi
      ;;
    *)
      ui_is_interactive || return 0
      ;;
  esac

  read -r -n 1 -p "$msg"
  echo
  return 0
}

ui_pause() {
  # 統一的暫停介面（建議新程式碼使用）
  # 用法：
  # - ui_pause ["訊息"]                # 互動終端才等待；CLI/非互動直接略過
  # - ui_pause ["訊息"] "main"         # 主選單暫停：CLI/非互動會輸出「已略過等待」提示
  set -- "${1:-按任意鍵返回...}" "${2:-interactive}"
  local msg="$1"
  local mode="$2"
  _ui_pause_impl "$msg" "$mode"
}

print_hr() {
  echo "=================================="
}

print_header() {
  local title="${1:-}"
  print_hr
  if [ -n "$title" ]; then
    echo "❖ $title ❖"
  fi
  print_hr
}

wait_keypress_if_interactive() {
  local msg="${1:-}"
  ui_is_interactive || return 0
  if [ -n "$msg" ]; then
    echo "$msg"
  fi
  read -r -n 1
  echo
}

_prompt_required() {
  local out_var="$1"
  local prompt="$2"
  local empty_message="$3"
  local value

  if ! ui_is_interactive; then
    tgdb_fail "非互動模式下不可使用互動輸入：$prompt" 2 || return $?
  fi

  while true; do
    read -r -e -p "$prompt" value
    if [ -n "$value" ]; then
      printf -v "$out_var" '%s' "$value"
      return 0
    fi
    echo "$empty_message"
  done
}

ui_confirm_yn() {
  local prompt="$1"
  local default="${2:-Y}"
  local answer

  if ! ui_is_interactive; then
    tgdb_fail "非互動模式下不可詢問確認：$prompt" 2 || return $?
  fi

  while true; do
    read -r -e -p "$prompt" answer
    case "$answer" in
      0) return 2 ;;
      "") answer="$default" ;;
    esac

    case "$answer" in
      Y|y) return 0 ;;
      N|n) return 1 ;;
      *)
        tgdb_err "請輸入 Y/n（或輸入 0 取消）。"
        ;;
    esac
  done
}

ui_prompt_index() {
  local out_var="$1"
  local prompt="$2"
  local min="${3:-0}"
  local max="${4:-0}"
  local default_value="${5:-}"
  local cancel_value="${6:-0}"

  if [ -z "$out_var" ] || [ -z "$prompt" ]; then
    tgdb_fail "ui_prompt_index 參數不足：<out_var> <prompt> <min> <max> [default] [cancel]" 2 || return $?
  fi

  if ! ui_is_interactive; then
    tgdb_fail "非互動模式下不可使用互動輸入：$prompt" 2 || return $?
  fi

  if [[ ! "$min" =~ ^[0-9]+$ ]] || [[ ! "$max" =~ ^[0-9]+$ ]]; then
    tgdb_fail "ui_prompt_index 參數錯誤：min/max 必須是非負整數" 2 || return $?
  fi

  if [ "$min" -gt "$max" ] 2>/dev/null; then
    tgdb_fail "ui_prompt_index 參數錯誤：min 不可大於 max" 2 || return $?
  fi

  local cancel_hint=""
  if [ -n "${cancel_value:-}" ]; then
    cancel_hint="（或輸入 $cancel_value 取消）"
  fi

  local value
  while true; do
    read -r -e -p "$prompt" value

    if [ -n "${cancel_value:-}" ] && [ "$value" = "$cancel_value" ]; then
      return 2
    fi

    if [ -z "$value" ] && [ -n "$default_value" ]; then
      value="$default_value"
    fi

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
      tgdb_err "請輸入數字${cancel_hint}。"
      continue
    fi

    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
      tgdb_err "請輸入範圍內的數字：$min-$max${cancel_hint}。"
      continue
    fi

    printf -v "$out_var" '%s' "$value"
    return 0
  done
}
