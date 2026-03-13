#!/bin/bash

# Kopia 管理：遠端 Repository 設定
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_MENU_REPO_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_MENU_REPO_LOADED=1

kopia_p_setup_remote_repository() {
  _kopia_require_interactive || return $?
  load_system_config >/dev/null 2>&1 || true

  if ! _kopia_is_installed; then
    tgdb_fail "尚未部署 Kopia，請先執行部署。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local runner
  runner="$(_kopia_runner_script)"
  if [ ! -f "$runner" ]; then
    tgdb_fail "找不到腳本：$runner" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  if ! command -v rclone >/dev/null 2>&1; then
    tgdb_fail "未偵測到 rclone，請先到 Rclone 管理完成安裝與遠端設定。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local remotes
  remotes="$(_kopia_list_rclone_remotes 2>/dev/null || true)"
  if [ -z "${remotes:-}" ]; then
    tgdb_fail "尚未偵測到 rclone 遠端，請先設定 $TGDB_DIR/rclone.conf。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  clear
  echo "=================================="
  echo "❖ Kopia 遠端 Repository 設定 ❖"
  echo "=================================="
  echo "可用 rclone 遠端："
  local i=1
  local -a remote_arr=()
  local r
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    echo "$i. $r"
    remote_arr+=("$r")
    i=$((i+1))
  done <<< "$remotes"
  echo "----------------------------------"
  echo "0. 返回"

  local idx
  if ! ui_prompt_index idx "請選擇遠端編號 [0-${#remote_arr[@]}]: " 1 "${#remote_arr[@]}" "" 0; then
    echo "操作已取消。"
    return 0
  fi
  local remote_name
  remote_name="${remote_arr[$((idx-1))]}"

  local repo_dir default_repo_dir
  default_repo_dir="tgdb/kopia"
  while true; do
    read -r -e -p "請輸入備份目錄名稱（預設 $default_repo_dir，輸入 0 取消）: " repo_dir
    if [ "${repo_dir:-}" = "0" ]; then
      echo "操作已取消。"
      return 0
    fi
    repo_dir="${repo_dir:-$default_repo_dir}"
    repo_dir="${repo_dir#/}"
    repo_dir="${repo_dir%/}"
    if [ -n "${repo_dir:-}" ]; then
      break
    fi
    tgdb_err "備份目錄不可為空。"
  done

  echo "⏳ 正在設定遠端 Repository（$remote_name:$repo_dir）..."
  if ! bash "$runner" repo-setup-rclone auto "$remote_name" "$repo_dir"; then
    tgdb_fail "遠端 Repository 設定失敗，請檢查 rclone 遠端與密碼設定。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "✅ 已完成遠端 Repository 設定。"
  echo "提示：備份請由你手動執行（排程選單的「立即執行一次」）或透過 timer 自動執行。"
  ui_pause "按任意鍵返回..."
  return 0
}
