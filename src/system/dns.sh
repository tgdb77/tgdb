#!/bin/bash

# 系統管理：DNS 設定；上游設定與 Tailscale stub 分離。
# 注意：此檔案會被 source，請勿更改 shell options。

# shellcheck source=src/core/dns.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/dns.sh"

dns_apply_servers() {
  require_root || return 1
  local SERVER CONTENT
  local -a SERVERS=()
  for SERVER in "$@"; do
    [ -n "$SERVER" ] || continue
    if ! tgdb_dns_valid_address "$SERVER"; then
      tgdb_err "DNS 位址格式不正確：$SERVER"
      return 1
    fi
    SERVERS+=("$SERVER")
  done
  if [ "${#SERVERS[@]}" -eq 0 ]; then
    tgdb_err "DNS 位址不可為空。"
    return 1
  fi

  if tgdb_dns_uses_resolved; then
    for SERVER in "${SERVERS[@]}"; do
      case "${SERVER,,}" in
        127.0.0.53|127.0.0.54|100.100.100.100|fd7a:115c:a1e0::53)
          tgdb_err "不可將 systemd-resolved／Tailscale 解析器設成自己的全域上游：$SERVER"
          return 1
          ;;
      esac
    done
    if ! tgdb_dns_migrate_legacy || ! tgdb_dns_write_resolved_servers "${SERVERS[*]}"; then
      tgdb_err "無法寫入 TGDB 上游 DNS 設定，尚未成功套用。"
      return 1
    fi
    tgdb_dns_restart_resolved || return 1
    echo "✅ 已透過 systemd-resolved 設定全域上游 DNS；保留 DHCP／Tailscale 的每介面 DNS。"
    return 0
  fi

  # 不跟隨 NetworkManager、resolvconf 等管理器的符號連結寫入暫存檔。
  if [ -L /etc/resolv.conf ] || grep -qi tailscale /etc/resolv.conf 2>/dev/null; then
    tgdb_err "/etc/resolv.conf 由其他解析管理器管理；請使用該管理器設定，或先啟用 systemd-resolved。"
    return 1
  fi
  CONTENT="$(printf '%s\n' '# 由 TGDB 設定的 DNS'; printf 'nameserver %s\n' "${SERVERS[@]}")"
  if ! tgdb_dns_write_file /etc/resolv.conf "$CONTENT"; then
    tgdb_err "無法更新 /etc/resolv.conf。"
    return 1
  fi
  echo "✅ /etc/resolv.conf 已更新；目前未使用 systemd-resolved，DHCP 仍可能覆寫此檔案。"
}

dns_restore_automatic() {
  require_root || return 1
  if ! tgdb_dns_uses_resolved; then
    tgdb_err "未使用 systemd-resolved，請透過 NetworkManager／DHCP 管理工具還原；未變更 /etc/resolv.conf。"
    return 1
  fi
  if ! tgdb_dns_migrate_legacy || ! _tgdb_run_privileged rm -f "$(tgdb_dns_resolved_config_path)"; then
    tgdb_err "無法移除 TGDB 上游 DNS 設定，尚未完成還原。"
    return 1
  fi
  tgdb_dns_restart_resolved || return 1
  echo "✅ 已移除 TGDB 固定上游 DNS；保留 Tailscale stub 與其他使用者設定，由系統管理 DNS。"
}

dns_edit_servers() {
  local TEMP EDITOR_COMMAND="${EDITOR:-}" DNS_TEXT CONFIG
  local -a SERVERS=()
  if [ -z "$EDITOR_COMMAND" ]; then
    if command -v nano >/dev/null 2>&1; then
      EDITOR_COMMAND="nano"
    elif command -v vi >/dev/null 2>&1; then
      EDITOR_COMMAND="vi"
    else
      tgdb_err "找不到編輯器，請設定 EDITOR 或安裝 nano／vi。"
      return 1
    fi
  fi

  TEMP="$(mktemp)" || return 1
  CONFIG="$(tgdb_dns_resolved_config_path)"
  # 編輯使用者的暫存草稿，儲存並驗證後才套用，絕不直接編輯 stub。
  if ! {
    printf '%s\n' '# 每行一個 DNS 位址，例如：nameserver 1.1.1.1' '# 支援 IPv4／IPv6；空白行與註解會忽略。'
    if [ -f "$CONFIG" ]; then
      awk '/^DNS=./ { sub(/^DNS=/, ""); for (i=1; i<=NF; i++) print "nameserver " $i }' "$CONFIG"
    elif [ -f /etc/resolv.conf ]; then
      awk '$1 == "nameserver" && $2 !~ /^127\./ && $2 != "::1" && $2 != "100.100.100.100" && tolower($2) != "fd7a:115c:a1e0::53" { print "nameserver " $2 }' /etc/resolv.conf
    fi
  } > "$TEMP"; then
    rm -f "$TEMP"
    return 1
  fi
  echo "請編輯 DNS 位址草稿；儲存後將套用至持久設定，不會直接修改解析服務的暫存檔。"
  if ! "$EDITOR_COMMAND" "$TEMP"; then
    tgdb_err "編輯器執行失敗，未變更 DNS。"
    rm -f "$TEMP"
    return 1
  fi
  if ! DNS_TEXT="$(awk '
    /^[[:space:]]*(#|$)/ { next }
    $1 == "nameserver" && NF == 2 { print $2; next }
    { exit 1 }
  ' "$TEMP")" || [ -z "$DNS_TEXT" ]; then
    tgdb_err "草稿格式不正確或未指定 DNS；每行請使用 nameserver <位址>。未變更 DNS。"
    rm -f "$TEMP"
    return 1
  fi
  rm -f "$TEMP"
  mapfile -t SERVERS <<< "$DNS_TEXT"
  dns_apply_servers "${SERVERS[@]}"
}

dns_print_state() {
  if tgdb_dns_uses_resolved; then
    echo "解析器：systemd-resolved（全域上游與每介面 DNS 分開管理）"
    if command -v resolvectl >/dev/null 2>&1 && resolvectl dns 2>/dev/null; then
      return 0
    fi
    if [ -f "$(tgdb_dns_resolved_config_path)" ]; then
      echo "TGDB 全域上游設定："
      grep '^DNS=.' "$(tgdb_dns_resolved_config_path)" || true
    fi
    echo "ℹ️ resolv.conf 的 127.0.0.53 是本機 stub，不是實際上游 DNS。"
  fi
  if [ -f /etc/resolv.conf ]; then
    grep '^nameserver' /etc/resolv.conf || true
  else
    echo "/etc/resolv.conf 不存在。"
  fi
}

manage_dns() {
  local DNS_CHOICE
  while true; do
    maybe_clear
    echo "=================================="
    echo "❖ 調整 DNS 位址 ❖"
    echo "=================================="
    dns_print_state
    echo "----------------------------------"
    echo "1. Cloudflare DNS (1.1.1.1, 1.0.0.1)"
    echo "2. Google DNS (8.8.8.8, 8.8.4.4)"
    echo "3. TGDB 預設 DNS (1.1.1.1, 8.8.8.8)"
    echo "4. 自訂 DNS（編輯位址草稿後套用）"
    echo "5. 還原為系統自動管理（移除 TGDB 上游 DNS）"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-5]: " DNS_CHOICE || return 0
    case "$DNS_CHOICE" in
      1) dns_apply_servers 1.1.1.1 1.0.0.1 || true ;;
      2) dns_apply_servers 8.8.8.8 8.8.4.4 || true ;;
      3) dns_apply_servers 1.1.1.1 8.8.8.8 || true ;;
      4) dns_edit_servers || true ;;
      5)
        if system_admin_confirm_yn "確定要移除 TGDB 固定上游 DNS 嗎？其他設定與 Tailscale DNS 會保留。(Y/n，預設 Y，輸入 0 取消): " "Y"; then
          dns_restore_automatic || true
        else
          echo "已取消還原。"
        fi
        ;;
      0) return 0 ;;
      *) tgdb_err "無效選項。" ;;
    esac
    pause
  done
}
