#!/bin/bash

# 第三方腳本：bin456789/reinstall
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_THIRD_PARTY_REINSTALL_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_THIRD_PARTY_REINSTALL_LOADED=1

THIRD_PARTY_REINSTALL_SCRIPT_URL="${THIRD_PARTY_REINSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh}"
THIRD_PARTY_REINSTALL_SCRIPT_PATH="${THIRD_PARTY_REINSTALL_SCRIPT_PATH:-/tmp/tgdb-reinstall.sh}"
THIRD_PARTY_REINSTALL_REBOOT_COMMAND=()

_third_party_reinstall_join_shell_words() {
  local out_var="$1"
  shift || true

  local joined=""
  local word=""
  for word in "$@"; do
    printf -v word '%q' "$word"
    joined="${joined}${joined:+ }${word}"
  done

  printf -v "$out_var" '%s' "$joined"
}

third_party_reinstall_detect_virtualization() {
  local virt=""
  local product_name=""
  local sys_vendor=""

  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    case "$virt" in
      kvm|qemu)
        printf '%s\n' "$virt"
        return 0
        ;;
    esac
  fi

  if [ -r /sys/class/dmi/id/product_name ]; then
    product_name="$(tr -d '\r\n' </sys/class/dmi/id/product_name 2>/dev/null || true)"
  fi
  if [ -r /sys/class/dmi/id/sys_vendor ]; then
    sys_vendor="$(tr -d '\r\n' </sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  fi

  case "${product_name} ${sys_vendor}" in
    *KVM*|*QEMU*)
      if [[ "${product_name} ${sys_vendor}" == *KVM* ]]; then
        printf '%s\n' "kvm"
      else
        printf '%s\n' "qemu"
      fi
      return 0
      ;;
  esac

  return 1
}

third_party_reinstall_print_menu() {
  clear || true
  echo "=================================="
  echo "❖ VPS 系統重裝 ❖"
  echo "=================================="
  echo "⚠️  警告⚠️ ：此操作會清空目前系統整顆硬碟的資料（含其他分割區）。"
  echo "⚠️  警告⚠️ ：執行後目前 SSH 連線可能中斷，TGDB 也不保證會保留。"
  echo "⚠️  警告⚠️ ：請先自行確認備份、救援模式、VNC 或主機商控台可用。"
  echo "----------------------------------"
  echo "1. Debian 13"
  echo "2. Ubuntu 24.04 LTS"
  echo "3. Fedora Linux 43"
  echo "4. Arch Linux"
  echo "5. Rocky Linux 10"
  echo "6. AlmaLinux 10"
  echo "7. openSUSE 16.0"
  echo "----------------------------------"
  echo "0. 返回"
  echo "=================================="
}

third_party_reinstall_collect_params() {
  local password=""
  local ssh_port=""
  local default_ssh_port=""

  THIRD_PARTY_REINSTALL_USERNAME="root"

  while true; do
    read -r -s -p "請輸入 root 密碼（輸入 0 取消）: " password
    echo
    if [ "$password" = "0" ]; then
      return 2
    fi
    if [ -n "$password" ]; then
      THIRD_PARTY_REINSTALL_PASSWORD="$password"
      break
    fi
    tgdb_err "密碼不可為空。"
  done

  default_ssh_port="$(detect_ssh_port 2>/dev/null || true)"
  default_ssh_port="${default_ssh_port:-22}"
  if ! ssh_port="$(prompt_port_number "請輸入新的 SSH 埠" "$default_ssh_port")"; then
    return $?
  fi
  THIRD_PARTY_REINSTALL_SSH_PORT="$ssh_port"
  return 0
}

third_party_reinstall_download_script() {
  local dest_path="${1:-$THIRD_PARTY_REINSTALL_SCRIPT_PATH}"

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL -o "$dest_path" "$THIRD_PARTY_REINSTALL_SCRIPT_URL"; then
      chmod +x "$dest_path" 2>/dev/null || true
      printf '%s\n' "$dest_path"
      return 0
    fi
  fi

  if command -v wget >/dev/null 2>&1; then
    if wget -O "$dest_path" "$THIRD_PARTY_REINSTALL_SCRIPT_URL"; then
      chmod +x "$dest_path" 2>/dev/null || true
      printf '%s\n' "$dest_path"
      return 0
    fi
  fi

  tgdb_fail "無法下載 reinstall 官方腳本。請確認 curl / wget 與網路連線是否正常。" 1 || return $?
}

third_party_reinstall_build_command() {
  local script_path="$1"
  local os_id="$2"
  local os_version="$3"
  local password="$4"
  local ssh_port="$5"

  THIRD_PARTY_REINSTALL_COMMAND=()
  if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
    THIRD_PARTY_REINSTALL_COMMAND=("bash" "$script_path" "$os_id")
  else
    THIRD_PARTY_REINSTALL_COMMAND=("sudo" "bash" "$script_path" "$os_id")
  fi
  if [ -n "$os_version" ]; then
    THIRD_PARTY_REINSTALL_COMMAND+=("$os_version")
  fi
  THIRD_PARTY_REINSTALL_COMMAND+=("--password" "$password" "--ssh-port" "$ssh_port")

  if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
    THIRD_PARTY_REINSTALL_REBOOT_COMMAND=("reboot")
  else
    THIRD_PARTY_REINSTALL_REBOOT_COMMAND=("sudo" "reboot")
  fi

  _third_party_reinstall_join_shell_words THIRD_PARTY_REINSTALL_COMMAND_PREVIEW "${THIRD_PARTY_REINSTALL_COMMAND[@]}"
  _third_party_reinstall_join_shell_words THIRD_PARTY_REINSTALL_REBOOT_COMMAND_PREVIEW "${THIRD_PARTY_REINSTALL_REBOOT_COMMAND[@]}"
  return 0
}

third_party_reinstall_confirm() {
  local os_label="$1"
  local confirm_yes=""

  clear || true
  echo "=================================="
  echo "❖ VPS 系統重裝：最終確認 ❖"
  echo "=================================="
  tgdb_warn "注意：下方會顯示完整執行指令，包含你輸入的密碼。"
  echo "目標系統：$os_label"
  echo "使用者名稱：$THIRD_PARTY_REINSTALL_USERNAME"
  echo "密碼：$THIRD_PARTY_REINSTALL_PASSWORD"
  echo "SSH 埠號：$THIRD_PARTY_REINSTALL_SSH_PORT"
  echo "腳本位置：$THIRD_PARTY_REINSTALL_DOWNLOADED_PATH"
  echo "----------------------------------"
  echo "重裝指令："
  echo "$THIRD_PARTY_REINSTALL_COMMAND_PREVIEW"
  echo "重開機指令："
  echo "$THIRD_PARTY_REINSTALL_REBOOT_COMMAND_PREVIEW"
  echo "ps：密碼帶有 \ 是正常現象"
  echo "----------------------------------"
  read -r -e -p "請輸入 YES 以確認立即重裝系統（其他輸入取消）: " confirm_yes
  [ "$confirm_yes" = "YES" ]
}

third_party_reinstall_run() {
  require_root || return 1

  clear || true
  echo "=================================="
  echo "❖ 開始執行 VPS 系統重裝 ❖"
  echo "=================================="
  echo "目標系統：$THIRD_PARTY_REINSTALL_TARGET_LABEL"
  echo "使用者名稱：$THIRD_PARTY_REINSTALL_USERNAME"
  echo "SSH 埠號：$THIRD_PARTY_REINSTALL_SSH_PORT"
  echo "重裝指令：$THIRD_PARTY_REINSTALL_COMMAND_PREVIEW"
  echo "重開機指令：$THIRD_PARTY_REINSTALL_REBOOT_COMMAND_PREVIEW"
  echo "----------------------------------"
  echo "即將執行官方重裝腳本；腳本完成後會立即重開機，系統將開始重裝。"
  echo ""

  "${THIRD_PARTY_REINSTALL_COMMAND[@]}"
  local rc=$?

  echo ""
  if [ "$rc" -ne 0 ]; then
    tgdb_warn "reinstall 腳本已結束（返回碼：$rc），請檢查上方輸出。"
    return "$rc"
  fi

  echo "✅ reinstall 腳本已完成，立即執行重開機..."
  "${THIRD_PARTY_REINSTALL_REBOOT_COMMAND[@]}"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    tgdb_warn "重開機指令執行失敗（返回碼：$rc），請手動執行：$THIRD_PARTY_REINSTALL_REBOOT_COMMAND_PREVIEW"
  fi
  return "$rc"
}

third_party_reinstall_menu() {
  local choice=""
  local os_id=""
  local os_version=""
  local os_label=""

  while true; do
    third_party_reinstall_print_menu
    read -r -e -p "請輸入選擇 [0-7]: " choice

    case "$choice" in
      1) os_id="debian"; os_version="13"; os_label="Debian 13" ;;
      2) os_id="ubuntu"; os_version="24.04"; os_label="Ubuntu 24.04 LTS" ;;
      3) os_id="fedora"; os_version="43"; os_label="Fedora Linux 43" ;;
      4) os_id="arch"; os_version=""; os_label="Arch Linux" ;;
      5) os_id="rocky"; os_version="10"; os_label="Rocky Linux 10" ;;
      6) os_id="almalinux"; os_version="10"; os_label="AlmaLinux 10" ;;
      7) os_id="opensuse"; os_version="16.0"; os_label="openSUSE 16.0" ;;
      0) return 0 ;;
      *)
        tgdb_err "無效選項"
        sleep 1
        continue
        ;;
    esac

    THIRD_PARTY_REINSTALL_TARGET_ID="$os_id"
    THIRD_PARTY_REINSTALL_TARGET_VERSION="$os_version"
    THIRD_PARTY_REINSTALL_TARGET_LABEL="$os_label"
    THIRD_PARTY_REINSTALL_USERNAME=""
    THIRD_PARTY_REINSTALL_PASSWORD=""
    THIRD_PARTY_REINSTALL_SSH_PORT=""
    THIRD_PARTY_REINSTALL_DOWNLOADED_PATH=""
    THIRD_PARTY_REINSTALL_COMMAND=()
    THIRD_PARTY_REINSTALL_REBOOT_COMMAND=()
    THIRD_PARTY_REINSTALL_COMMAND_PREVIEW=""
    THIRD_PARTY_REINSTALL_REBOOT_COMMAND_PREVIEW=""

    if ! third_party_reinstall_collect_params; then
      case "$?" in
        2) continue ;;
        *)
          ui_pause "參數收集失敗，按任意鍵返回..." "main"
          continue
          ;;
      esac
    fi

    if ! THIRD_PARTY_REINSTALL_DOWNLOADED_PATH="$(third_party_reinstall_download_script "$THIRD_PARTY_REINSTALL_SCRIPT_PATH")"; then
      ui_pause "下載官方腳本失敗，按任意鍵返回..." "main"
      continue
    fi

    if ! third_party_reinstall_build_command \
      "$THIRD_PARTY_REINSTALL_DOWNLOADED_PATH" \
      "$THIRD_PARTY_REINSTALL_TARGET_ID" \
      "$THIRD_PARTY_REINSTALL_TARGET_VERSION" \
      "$THIRD_PARTY_REINSTALL_PASSWORD" \
      "$THIRD_PARTY_REINSTALL_SSH_PORT"; then
      ui_pause "組合執行指令失敗，按任意鍵返回..." "main"
      continue
    fi

    if ! third_party_reinstall_confirm "$THIRD_PARTY_REINSTALL_TARGET_LABEL"; then
      tgdb_warn "已取消重裝。"
      ui_pause "按任意鍵返回..." "main"
      continue
    fi

    third_party_reinstall_run
    local run_rc=$?
    ui_pause "執行結束，按任意鍵返回..." "main"
    return "$run_rc"
  done
}

third_party_run_reinstall() {
  local virt_type=""

  if ! virt_type="$(third_party_reinstall_detect_virtualization)"; then
    tgdb_warn "VPS 系統重裝目前僅支援 KVM 虛擬化技術。"
    ui_pause "按任意鍵返回上一頁..." "main"
    return 0
  fi

  require_root || {
    ui_pause "此功能需要 root 或 sudo 權限，按任意鍵返回..." "main"
    return 1
  }

  tgdb_info "已偵測到虛擬化類型：$virt_type"
  third_party_reinstall_menu
}
