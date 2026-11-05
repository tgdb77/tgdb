# Tailscale 官方 Linux DNS 建議：https://tailscale.com/kb/1188/linux-dns
# 使用 systemd-resolved 的 stub，避免 DHCP／NetworkManager 與 Tailscale 爭寫 resolv.conf。

# shellcheck source=src/core/dns.sh
source "$SRC_ROOT/core/dns.sh"

_tailscale_p_prepare_systemd_resolved() {
  if ! command -v systemctl >/dev/null 2>&1 || ! systemctl show --property=Version --value >/dev/null 2>&1; then
    tgdb_err "DNS 前置設定需要正在運作的 systemd，已停止安裝 Tailscale。"
    return 1
  fi

  local RESOLV_CONF="/etc/resolv.conf"
  local STUB_CONF="/run/systemd/resolve/stub-resolv.conf"
  local DROP_IN
  DROP_IN="$(tgdb_dns_tailscale_config_path)"
  local BACKUP="" ORIGINAL_DNS="" WAS_ACTIVE=0 RESTART_NM=0

  systemctl is-active --quiet systemd-resolved && WAS_ACTIVE=1
  if [ "$(readlink "$RESOLV_CONF" 2>/dev/null)" != "$STUB_CONF" ]; then
    RESTART_NM=1
  fi
  [ "$WAS_ACTIVE" -eq 0 ] && RESTART_NM=1

  # 安裝 systemd-resolved 套件時也可能改寫 resolv.conf，必須先備份。
  if [ -e "$RESOLV_CONF" ] || [ -L "$RESOLV_CONF" ]; then
    BACKUP="$(_tailscale_p_sudo mktemp /etc/resolv.conf.tgdb-backup.XXXXXX)" || return 1
    _tailscale_p_sudo cp -a --remove-destination "$RESOLV_CONF" "$BACKUP" || return 1
    echo "ℹ️ 原本的 DNS 設定已備份：$BACKUP"
    ORIGINAL_DNS="$(awk '
      $1 == "nameserver" && $2 !~ /^127\./ && $2 != "::1" &&
      $2 != "0.0.0.0" && $2 != "::" && $2 != "100.100.100.100" &&
      $2 != "fd7a:115c:a1e0::53" && !seen[$2]++ { printf "%s ", $2 }
    ' "$RESOLV_CONF" 2>/dev/null)"
  fi

  # 舊版上游設定先搬至共用 DNS 檔；後續切換／還原皆由系統 DNS 模組管理。
  if ! tgdb_dns_migrate_legacy; then
    tgdb_err "舊版 DNS 設定遷移失敗，已停止安裝。"
    _tailscale_p_restore_resolv_conf "$BACKUP"
    return 1
  fi
  if [ "$WAS_ACTIVE" -eq 0 ] && ! tgdb_dns_preserve_resolved_servers "${ORIGINAL_DNS% }"; then
    tgdb_err "無法保留原本的上游 DNS，已停止安裝。"
    _tailscale_p_restore_resolv_conf "$BACKUP"
    return 1
  fi

  if ! systemctl cat systemd-resolved.service >/dev/null 2>&1; then
    tgdb_warn "未偵測到 systemd-resolved，將先安裝套件..."
    if ! install_package systemd-resolved; then
      _tailscale_p_restore_resolv_conf "$BACKUP"
      return 1
    fi
  fi

  # Tailscale 專用檔只設定 stub，絕不混入全域上游 DNS。
  if ! tgdb_dns_write_file "$DROP_IN" $'[Resolve]\nDNSStubListener=yes'; then
    tgdb_err "無法建立 systemd-resolved stub 設定，已停止安裝。"
    _tailscale_p_restore_resolv_conf "$BACKUP"
    return 1
  fi

  if ! _tailscale_p_sudo systemctl enable --now systemd-resolved ||
     ! _tailscale_p_sudo ln -sfn "$STUB_CONF" "$RESOLV_CONF" ||
     ! _tailscale_p_sudo systemctl restart systemd-resolved; then
    tgdb_err "systemd-resolved 啟用或 stub 設定失敗，已停止安裝。"
    _tailscale_p_restore_resolv_conf "$BACKUP"
    return 1
  fi

  # 僅在切換解析器時重啟已運作的 NetworkManager，避免每次更新都中斷網路。
  if [ "$RESTART_NM" -eq 1 ] && systemctl is-active --quiet NetworkManager; then
    if ! _tailscale_p_sudo systemctl restart NetworkManager; then
      tgdb_err "NetworkManager 重新啟動失敗，已停止安裝。"
      _tailscale_p_restore_resolv_conf "$BACKUP"
      return 1
    fi
  fi

  if [ ! -s "$STUB_CONF" ] || ! getent ahosts tailscale.com >/dev/null 2>&1; then
    tgdb_err "DNS 前置設定後無法解析 tailscale.com，已停止安裝；請檢查上游 DNS 與 53 埠。"
    _tailscale_p_restore_resolv_conf "$BACKUP"
    return 1
  fi

  echo "✅ 已啟用 systemd-resolved，並將 /etc/resolv.conf 指向 stub。"
  return 0
}

_tailscale_p_restore_resolv_conf() {
  local BACKUP="${1:-}"
  [ -n "$BACKUP" ] || return 0
  if _tailscale_p_sudo cp -a --remove-destination "$BACKUP" /etc/resolv.conf; then
    tgdb_warn "已還原原本的 /etc/resolv.conf；備份保留於 $BACKUP。"
  else
    tgdb_err "無法還原 /etc/resolv.conf，請從 $BACKUP 手動還原。"
  fi
}
