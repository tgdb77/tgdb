#!/bin/bash

# Taildrive 檔案分享管理（Tailscale 子模組）
# Taildrive 透過 Tailscale 內建 WebDAV 服務持續分享資料夾；實際存取權限由 Tailnet 政策控制。

_tailscale_p_version_at_least() {
  local current="$1" minimum="$2"
  local -a current_parts minimum_parts
  local i current_value minimum_value

  IFS='.' read -r -a current_parts <<< "${current#v}"
  IFS='.' read -r -a minimum_parts <<< "${minimum#v}"
  for i in 0 1 2; do
    current_value="${current_parts[$i]:-0}"
    minimum_value="${minimum_parts[$i]:-0}"
    current_value="${current_value%%[^0-9]*}"
    minimum_value="${minimum_value%%[^0-9]*}"
    current_value="${current_value:-0}"
    minimum_value="${minimum_value:-0}"
    if [ "$current_value" -gt "$minimum_value" ]; then
      return 0
    fi
    if [ "$current_value" -lt "$minimum_value" ]; then
      return 1
    fi
  done
  return 0
}

_tailscale_p_drive_version() {
  tailscale version 2>/dev/null | awk 'NR == 1 { print $1 }' | sed 's/^v//'
}

_tailscale_p_drive_require_ready() {
  if ! command -v tailscale >/dev/null 2>&1; then
    tgdb_err "尚未安裝 tailscale，請先執行「安裝/更新 tailscale 客戶端」。"
    return 1
  fi

  local version
  version="$(_tailscale_p_drive_version)"
  if [ -z "$version" ] || ! _tailscale_p_version_at_least "$version" "1.64.0"; then
    tgdb_err "Taildrive 需要 Tailscale 1.64.0 以上；目前版本：${version:-無法取得}。"
    return 1
  fi

  if ! _tailscale_p_sudo tailscale drive --help >/dev/null 2>&1; then
    tgdb_err "目前 tailscale 不支援 Taildrive，請先更新 tailscale 客戶端。"
    return 1
  fi

  if [ "$(_tailscale_p_current_state)" != "up" ]; then
    tgdb_err "Tailscale 尚未連線，請先使用「切換 tailscale(up/down）」連線。"
    return 1
  fi

  return 0
}

_tailscale_p_drive_print_policy_hint() {
  echo "啟用前置條件（請由 Tailnet 管理員在政策檔設定）："
  echo "文件：https://tailscale.com/docs/features/taildrive"
}

_tailscale_p_drive_prompt_share_name() {
  local out_var="$1" input=""
  while true; do
    read -r -e -p "請輸入分享名稱（輸入 0 取消）: " input
    [ "$input" = "0" ] && return 2
    if [ -z "$input" ] || [[ "$input" == -* ]] || [[ "$input" == */* ]] || [[ "$input" =~ [[:space:]] ]]; then
      tgdb_err "分享名稱不可為空、不可含空白或 /，且不可用 - 開頭。"
      continue
    fi
    printf -v "$out_var" '%s' "$input"
    return 0
  done
}

_tailscale_p_drive_prompt_directory() {
  local out_var="$1" input="" resolved=""
  while true; do
    read -r -e -p "請輸入要持續同步的資料夾絕對路徑（輸入 0 取消）: " input
    [ "$input" = "0" ] && return 2
    if [[ "$input" != /* ]]; then
      tgdb_err "請輸入絕對路徑。"
      continue
    fi
    if [ ! -d "$input" ]; then
      tgdb_err "找不到資料夾：$input"
      continue
    fi
    resolved="$(realpath -e "$input" 2>/dev/null || readlink -f "$input" 2>/dev/null || true)"
    if [ -z "$resolved" ] || [ ! -d "$resolved" ]; then
      tgdb_err "無法取得資料夾的實際路徑：$input"
      continue
    fi
    printf -v "$out_var" '%s' "$resolved"
    return 0
  done
}

tailscale_p_drive_share() {
  local name="" path=""
  _tailscale_p_drive_prompt_share_name name || return $?
  _tailscale_p_drive_prompt_directory path || return $?

  echo "將分享資料夾：$path"
  echo "分享名稱：$name"
  if ! ui_confirm_yn "確定建立/更新此 Taildrive 分享？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    return 0
  fi

  if _tailscale_p_sudo tailscale drive share "$name" "$path"; then
    echo "✅ 已建立 Taildrive 分享：$name"
    echo "其他獲授權裝置可透過 http://100.100.100.100:8080 存取。"
  else
    tgdb_err "建立分享失敗。請確認 Tailnet 政策已授予 drive:share 與對應 grants。"
  fi
}

tailscale_p_drive_list() {
  echo "=================================="
  echo "❖ Taildrive 分享清單 ❖"
  echo "=================================="
  _tailscale_p_sudo tailscale drive list || tgdb_err "無法讀取 Taildrive 分享清單。"
}

tailscale_p_drive_rename() {
  local old_name="" new_name=""
  _tailscale_p_drive_prompt_share_name old_name || return $?
  _tailscale_p_drive_prompt_share_name new_name || return $?
  _tailscale_p_sudo tailscale drive rename "$old_name" "$new_name" || tgdb_err "重新命名失敗，請確認分享名稱是否存在。"
}

tailscale_p_drive_unshare() {
  local name=""
  _tailscale_p_drive_prompt_share_name name || return $?
  if ! ui_confirm_yn "確定停止分享「$name」嗎？原始資料夾不會被刪除。(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    return 0
  fi
  _tailscale_p_sudo tailscale drive unshare "$name" || tgdb_err "停止分享失敗，請確認分享名稱是否存在。"
}

_tailscale_p_drive_print_menu_summary() {
  local output="" rc=0

  echo "❖ 目前分享 ❖"
  if ! command -v tailscale >/dev/null 2>&1 || ! _tailscale_p_sudo tailscale drive --help >/dev/null 2>&1; then
    echo "尚未可用（請安裝 Tailscale 1.64.0 以上並完成連線）。"
  else
    output="$(_tailscale_p_sudo tailscale drive list 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "目前無法讀取分享清單；請確認 Tailscale 已連線且政策已啟用 Taildrive。"
    elif [ -n "$output" ]; then
      printf '%s\n' "$output"
    else
      echo "目前沒有分享資料夾。"
    fi
  fi

  _tailscale_p_drive_print_policy_hint
}

tailscale_p_drive_menu() {
  _tailscale_p_require_tty || return $?
  _tailscale_p_require_sudo || { ui_pause "按任意鍵返回..."; return 1; }

  while true; do
    clear
    echo "=================================="
    echo "❖ Taildrive 檔案同步 ❖"
    echo "=================================="
    echo "以 Tailscale WebDAV 持續分享資料夾；權限由 Tailnet 政策控制。"
    _tailscale_p_drive_print_menu_summary
    echo "----------------------------------"
    echo "1. 建立/更新資料夾分享"
    echo "2. 重新命名分享"
    echo "3. 停止分享資料夾"
    echo "----------------------------------"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-3]: " choice

    case "$choice" in
      1)
        if _tailscale_p_drive_require_ready; then
          tailscale_p_drive_share || true
        fi
        ui_pause "按任意鍵返回..."
        ;;
      2)
        if _tailscale_p_drive_require_ready; then
          tailscale_p_drive_rename || true
        fi
        ui_pause "按任意鍵返回..."
        ;;
      3)
        if _tailscale_p_drive_require_ready; then
          tailscale_p_drive_unshare || true
        fi
        ui_pause "按任意鍵返回..."
        ;;
      0) return 0 ;;
      *) tgdb_err "無效選項"; ui_pause "按任意鍵返回..." ;;
    esac
  done
}
