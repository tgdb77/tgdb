#!/bin/bash

# DNS 共用設定：上游 DNS 與 Tailscale stub 分開管理，避免清單累加與還原遺漏。
# 注意：此檔案會被 source，請勿更改 shell options。

tgdb_dns_resolved_config_path() {
  printf '%s\n' /etc/systemd/resolved.conf.d/90-tgdb-dns.conf
}

tgdb_dns_tailscale_config_path() {
  printf '%s\n' /etc/systemd/resolved.conf.d/zz-tgdb-tailscale.conf
}

tgdb_dns_uses_resolved() {
  local TARGET
  TARGET="$(readlink -f /etc/resolv.conf 2>/dev/null || readlink /etc/resolv.conf 2>/dev/null || true)"
  case "$TARGET" in
    /run/systemd/resolve/*) return 0 ;;
  esac
  [ -e "$(tgdb_dns_resolved_config_path)" ] && return 0
  [ -e "$(tgdb_dns_tailscale_config_path)" ] && return 0
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-active --quiet systemd-resolved 2>/dev/null ||
    systemctl is-enabled --quiet systemd-resolved 2>/dev/null
}

tgdb_dns_write_file() {
  local PATH_NAME="$1" CONTENT="$2" TEMP
  _tgdb_run_privileged mkdir -p "$(dirname "$PATH_NAME")" || return 1
  TEMP="$(_tgdb_run_privileged mktemp "${PATH_NAME}.tmp.XXXXXX")" || return 1
  if ! (set -o pipefail; printf '%s\n' "$CONTENT" | _tgdb_run_privileged tee "$TEMP" >/dev/null) ||
     ! _tgdb_run_privileged chmod 644 "$TEMP" ||
     ! _tgdb_run_privileged mv -f "$TEMP" "$PATH_NAME"; then
    _tgdb_run_privileged rm -f "$TEMP" || true
    return 1
  fi
}

tgdb_dns_write_resolved_servers() {
  local CONTENT
  # 空的 DNS= 清除先前的全域清單；不變更 DHCP／Tailscale 的每介面 DNS。
  CONTENT="$(printf '%s\n' '[Resolve]' '# 由 TGDB 管理的全域上游 DNS' 'DNS=' "DNS=$1" 'FallbackDNS=')"
  tgdb_dns_write_file "$(tgdb_dns_resolved_config_path)" "$CONTENT"
}

tgdb_dns_legacy_main_config() {
  [ -f /etc/systemd/resolved.conf ] || return 1
  # 只辨識舊版 TGDB 寫出的最小格式，不移除含其他設定的使用者檔案。
  awk '
    /^[[:space:]]*$/ { next }
    /^\[Resolve\]$/ { section++; next }
    /^DNS=/ { dns++; next }
    /^FallbackDNS=$/ { fallback++; next }
    { other=1 }
    END { exit !(section == 1 && dns == 1 && fallback == 1 && !other) }
  ' /etc/systemd/resolved.conf
}

tgdb_dns_migrate_legacy() {
  local MAIN_DNS="" TAILSCALE_DNS="" FILE MAIN_LEGACY=0
  FILE="$(tgdb_dns_tailscale_config_path)"
  if tgdb_dns_legacy_main_config; then
    MAIN_LEGACY=1
    MAIN_DNS="$(awk '/^DNS=/ { sub(/^DNS=/, ""); print }' /etc/systemd/resolved.conf)"
  fi
  if [ -f "$FILE" ]; then
    TAILSCALE_DNS="$(awk '/^[[:space:]]*DNS[[:space:]]*=/ { sub(/^[[:space:]]*DNS[[:space:]]*=[[:space:]]*/, ""); if (length) print }' "$FILE")"
    TAILSCALE_DNS="${TAILSCALE_DNS//$'\n'/ }"
  fi

  # 已有共用設定時不覆寫；否則優先保留使用者最後透過舊 DNS 選單指定的值。
  if [ ! -e "$(tgdb_dns_resolved_config_path)" ]; then
    if [ -n "$MAIN_DNS" ]; then
      tgdb_dns_write_resolved_servers "$MAIN_DNS" || return 1
    elif [ -n "$TAILSCALE_DNS" ]; then
      tgdb_dns_write_resolved_servers "$TAILSCALE_DNS" || return 1
    fi
  fi

  if [ "$MAIN_LEGACY" -eq 1 ]; then
    if [ ! -e /etc/systemd/resolved.conf.tgdb-before-dns-migration ]; then
      _tgdb_run_privileged cp -a /etc/systemd/resolved.conf /etc/systemd/resolved.conf.tgdb-before-dns-migration || return 1
    fi
    _tgdb_run_privileged sed -i '/^DNS=/d; /^FallbackDNS=/d' /etc/systemd/resolved.conf || return 1
  fi
  if [ -f "$FILE" ] && grep -qE '^[[:space:]]*DNS[[:space:]]*=' "$FILE"; then
    if [ ! -e "${FILE}.tgdb-before-dns-migration" ]; then
      _tgdb_run_privileged cp -a "$FILE" "${FILE}.tgdb-before-dns-migration" || return 1
    fi
    _tgdb_run_privileged sed -i -E '/^[[:space:]]*DNS[[:space:]]*=/d' "$FILE" || return 1
  fi
}

tgdb_dns_preserve_resolved_servers() {
  [ -n "${1:-}" ] || return 0
  [ -e "$(tgdb_dns_resolved_config_path)" ] && return 0
  tgdb_dns_write_resolved_servers "$1"
}

tgdb_dns_restart_resolved() {
  # restart 也會啟動已停止的服務，不能因暫時停止就轉而寫入 stub 檔案。
  if ! command -v systemctl >/dev/null 2>&1 ||
     ! _tgdb_run_privileged systemctl restart systemd-resolved; then
    tgdb_err "systemd-resolved 啟動／重新啟動失敗，DNS 設定尚未成功套用。"
    return 1
  fi
  if [ ! -s /run/systemd/resolve/stub-resolv.conf ] ||
     ! _tgdb_run_privileged ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf; then
    tgdb_err "無法設定 systemd-resolved stub 連結，DNS 設定尚未成功套用。"
    return 1
  fi
}

tgdb_dns_valid_address() {
  local ADDRESS="$1" PART REST
  local -a PARTS=()
  if [[ "$ADDRESS" != *:* ]]; then
    [[ "$ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS='.' read -r -a PARTS <<< "$ADDRESS"
    for PART in "${PARTS[@]}"; do
      [ "${#PART}" -le 3 ] && [ "$((10#$PART))" -le 255 ] || return 1
      [[ "$PART" == 0 || "$PART" != 0* ]] || return 1
    done
    return 0
  fi
  # IPv4 映射的 IPv6 尾段佔兩組。
  if [[ "$ADDRESS" == *.* ]]; then
    tgdb_dns_valid_address "${ADDRESS##*:}" || return 1
    ADDRESS="${ADDRESS%:*}:0:0"
  fi
  [[ "$ADDRESS" =~ ^[[:xdigit:]:]+$ && "$ADDRESS" != *:::* ]] || return 1
  [[ "$ADDRESS" != :* || "$ADDRESS" == ::* ]] || return 1
  [[ "$ADDRESS" != *: || "$ADDRESS" == *:: ]] || return 1
  if [[ "$ADDRESS" == *::* ]]; then
    REST="${ADDRESS/::/}"
    [[ "$REST" != *::* ]] || return 1
  else
    [[ "$ADDRESS" != :* && "$ADDRESS" != *: ]] || return 1
  fi
  read -r -a PARTS <<< "${ADDRESS//:/ }"
  for PART in "${PARTS[@]}"; do
    [ "${#PART}" -le 4 ] || return 1
  done
  if [[ "$ADDRESS" == *::* ]]; then
    [ "${#PARTS[@]}" -lt 8 ]
  else
    [ "${#PARTS[@]}" -eq 8 ]
  fi
}
