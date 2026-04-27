#!/bin/bash

# Nginx WAF（ModSecurity + OWASP CRS）維護腳本
# 注意：此腳本可被 systemd timer 直接呼叫，也可手動執行。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SCRIPT_DIR/../../core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SCRIPT_DIR/../../core/quadlet_common.sh"

_init_tgdb_dir() {
  if [ -n "${TGDB_DIR:-}" ]; then
    return 0
  fi

  load_system_config || true
  if [ -z "${TGDB_DIR:-}" ]; then
    TGDB_DIR="${HOME:-/tmp}/.tgdb/app"
  fi
}

_init_tgdb_dir

NGINX_CONTAINER="${NGINX_CONTAINER:-nginx}"
NGINX_WAF_DIR="${NGINX_WAF_DIR:-$TGDB_DIR/nginx/modsecurity}"
CRS_DIR="${CRS_DIR:-$NGINX_WAF_DIR/crs}"
CRS_VERSION_FILE="${CRS_VERSION_FILE:-$NGINX_WAF_DIR/crs.version}"
USER_SYSTEMD_DIR="${USER_SYSTEMD_DIR:-$HOME/.config/systemd/user}"
CRS_REPO="${CRS_REPO:-coreruleset/coreruleset}"
CRS_LATEST_API="${CRS_LATEST_API:-https://api.github.com/repos/$CRS_REPO/releases/latest}"

_ensure_waf_dirs() {
  mkdir -p "$NGINX_WAF_DIR"
}

_exec_nginx_test_reload_if_running() {
  if ! podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$NGINX_CONTAINER"; then
    return 0
  fi

  if podman exec "$NGINX_CONTAINER" nginx -t; then
    podman exec "$NGINX_CONTAINER" nginx -s reload || true
    return 0
  fi

  tgdb_fail "Nginx 配置驗證失敗，CRS 已更新但尚未套用。" 1 || true
  return 1
}

_fetch_latest_crs_tag() {
  curl -fsSL "$CRS_LATEST_API" 2>/dev/null \
    | sed -nE 's/^[[:space:]]*"tag_name":[[:space:]]*"([^"]+)".*$/\1/p' \
    | head -n1
}

cmd_sync_crs() {
  _ensure_waf_dirs

  if ! command -v curl >/dev/null 2>&1; then
    tgdb_fail "找不到 curl，無法更新 CRS 規則。" 1 || true
    return 1
  fi
  if ! command -v tar >/dev/null 2>&1; then
    tgdb_fail "找不到 tar，無法更新 CRS 規則。" 1 || true
    return 1
  fi

  local tag
  tag="$(_fetch_latest_crs_tag || true)"
  if [ -z "${tag:-}" ]; then
    tgdb_fail "無法取得 OWASP CRS 最新版本標籤（GitHub API）。" 1 || true
    return 1
  fi

  local tmp_dir tarball tar_url src_dir build_dir
  tmp_dir="$(mktemp -d /tmp/tgdb-nginx-crs.XXXXXX 2>/dev/null || mktemp -d)"
  tarball="$tmp_dir/crs.tar.gz"
  tar_url="https://github.com/${CRS_REPO}/archive/refs/tags/${tag}.tar.gz"

  echo "下載 OWASP CRS 規則中：$tag"
  if ! curl -fL --retry 2 --connect-timeout 20 -o "$tarball" "$tar_url"; then
    rm -rf "$tmp_dir" 2>/dev/null || true
    tgdb_fail "CRS 規則下載失敗：$tar_url" 1 || true
    return 1
  fi

  if ! tar -xzf "$tarball" -C "$tmp_dir"; then
    rm -rf "$tmp_dir" 2>/dev/null || true
    tgdb_fail "CRS 壓縮檔解壓失敗。" 1 || true
    return 1
  fi

  src_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d -name 'coreruleset-*' | head -n1)"
  if [ -z "${src_dir:-}" ] || [ ! -d "$src_dir/rules" ]; then
    rm -rf "$tmp_dir" 2>/dev/null || true
    tgdb_fail "CRS 規則內容格式異常（找不到 rules 目錄）。" 1 || true
    return 1
  fi

  build_dir="$tmp_dir/crs.new"
  mkdir -p "$build_dir"
  cp -a "$src_dir/rules" "$build_dir/"

  if [ ! -f "$src_dir/crs-setup.conf.example" ]; then
    rm -rf "$tmp_dir" 2>/dev/null || true
    tgdb_fail "CRS 規則內容格式異常（找不到 crs-setup.conf.example）。" 1 || true
    return 1
  fi

  cp "$src_dir/crs-setup.conf.example" "$build_dir/crs-setup.conf.example"
  if [ -f "$CRS_DIR/crs-setup.conf" ]; then
    cp "$CRS_DIR/crs-setup.conf" "$build_dir/crs-setup.conf"
  else
    cp "$src_dir/crs-setup.conf.example" "$build_dir/crs-setup.conf"
  fi

  printf '%s\n' "$tag" > "$build_dir/.tgdb-crs-version"
  date -u +%FT%TZ > "$build_dir/.tgdb-updated-at"

  local backup_dir
  backup_dir="$NGINX_WAF_DIR/crs.bak.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
  if [ -d "$CRS_DIR" ]; then
    mv "$CRS_DIR" "$backup_dir"
  fi

  if ! mv "$build_dir" "$CRS_DIR"; then
    if [ -d "$backup_dir" ]; then
      mv "$backup_dir" "$CRS_DIR" 2>/dev/null || true
    fi
    rm -rf "$tmp_dir" 2>/dev/null || true
    tgdb_fail "更新 CRS 規則時發生錯誤（替換目錄失敗）。" 1 || true
    return 1
  fi

  rm -rf "$backup_dir" 2>/dev/null || true
  rm -rf "$tmp_dir" 2>/dev/null || true

  printf '%s\n' "$tag" > "$CRS_VERSION_FILE"
  echo "✅ 已更新 OWASP CRS 規則：$tag"

  _exec_nginx_test_reload_if_running
}

_write_user_unit() {
  mkdir -p "$USER_SYSTEMD_DIR"
  printf '%b' "$2" > "$USER_SYSTEMD_DIR/$1"
}

cmd_setup_timer() {
  local svc="tgdb-nginx-waf-crs-update.service"
  local tim="tgdb-nginx-waf-crs-update.timer"
  local script_abs="$SCRIPT_DIR/nginx-waf-maint.sh"

  _write_user_unit "$svc" "[Unit]\nDescription=TGDB Nginx WAF CRS Rule Update\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$script_abs\" sync-crs\n"
  _write_user_unit "$tim" "[Unit]\nDescription=Every 14 days update OWASP CRS rules\n\n[Timer]\nOnBootSec=10m\nOnUnitActiveSec=14d\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"

  _systemctl_user_try daemon-reload || true
  _systemctl_user_try enable --now -- "$tim" || true
  echo "✅ 已安裝並啟用 timer：$tim（每 14 天更新 CRS）"
}

cmd_remove_timer() {
  local units=(tgdb-nginx-waf-crs-update.timer tgdb-nginx-waf-crs-update.service)
  local u
  for u in "${units[@]}"; do
    _systemctl_user_try disable --now -- "$u" || true
    rm -f "$USER_SYSTEMD_DIR/$u" 2>/dev/null || true
  done
  _systemctl_user_try daemon-reload || true
  echo "✅ 已移除 WAF CRS 更新 timer"
}

cmd_status() {
  local version="unknown"
  if [ -f "$CRS_VERSION_FILE" ]; then
    version="$(head -n1 "$CRS_VERSION_FILE" 2>/dev/null || echo unknown)"
  fi
  echo "CRS 版本：$version"
  _systemctl_user_try list-timers --all | awk 'NR==1 || /tgdb-nginx-waf-crs-update/' || true
}

usage() {
  cat <<USAGE
用法: $0 <sync-crs|setup-timer|remove-timer|status>
USAGE
}

main() {
  local subcmd="${1:-}"
  case "$subcmd" in
    sync-crs) shift; cmd_sync_crs "$@" ;;
    setup-timer) shift; cmd_setup_timer "$@" ;;
    remove-timer) shift; cmd_remove_timer "$@" ;;
    status) shift; cmd_status "$@" ;;
    *) usage; return 1 ;;
  esac
}

if main "$@"; then
  exit 0
else
  exit $?
fi
