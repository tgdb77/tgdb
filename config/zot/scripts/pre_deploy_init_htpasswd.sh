#!/usr/bin/env bash

# Zot 部署前初始化：產生 bcrypt htpasswd（供 Zot auth.htpasswd 使用）
#
# 說明：
# - 本腳本由 AppSpec `pre_deploy=` 呼叫（設定檔產生後、啟動單元前執行）
# - 需可重複執行（idempotent），每次部署會覆寫 htpasswd
# - Zot 的 htpasswd 需要 bcrypt 格式（$2a$/$2b$...）
#
# 參數：
#   $1 service（預設 zot）
#   $2 name（container name）
#   $3 instance_dir
#   $4 host_port（未使用）
#
# 依賴：
# - 優先使用 mkpasswd（whois 套件；支援 bcrypt）
# - 次選使用 htpasswd（apache2-utils / httpd-tools）

set -euo pipefail

service="${1:-zot}"
name="${2:-}"
instance_dir_arg="${3:-}"

INSTANCE_DIR="${instance_dir:-${instance_dir_arg:-}}"
if [ -z "$INSTANCE_DIR" ] && [ -n "${TGDB_DIR:-}" ] && [ -n "${name:-}" ]; then
  INSTANCE_DIR="$TGDB_DIR/$name"
fi
if [ -z "$INSTANCE_DIR" ]; then
  echo "❌ 無法判斷 instance_dir（$service/$name）。" >&2
  exit 1
fi

USER_NAME="${user_name:-${ZOT_USER:-}}"
PASS_WORD="${pass_word:-${ZOT_PASSWORD:-}}"

if [ -z "${USER_NAME:-}" ]; then
  echo "❌ 缺少 Zot 帳號（$service/$name）。" >&2
  exit 1
fi
if [ -z "${PASS_WORD:-}" ]; then
  echo "❌ 缺少 Zot 密碼（$service/$name）。" >&2
  exit 1
fi

htpasswd_path="$INSTANCE_DIR/etc/htpasswd"
mkdir -p "$(dirname "$htpasswd_path")"

tmp="${htpasswd_path}.tmp.$$"
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT

if command -v mkpasswd >/dev/null 2>&1; then
  hash="$(printf '%s\n' "$PASS_WORD" | mkpasswd --method=bcrypt --stdin 2>/dev/null || true)"
  if [ -z "$hash" ]; then
    echo "❌ mkpasswd 產生 bcrypt 失敗（$service/$name）。" >&2
    exit 1
  fi
  printf '%s:%s\n' "$USER_NAME" "$hash" >"$tmp"
elif command -v htpasswd >/dev/null 2>&1; then
  # shellcheck disable=SC2005 # 需捕捉 htpasswd stderr 以避免密碼外洩
  if ! printf '%s\n' "$PASS_WORD" | htpasswd -Bni "$USER_NAME" >"$tmp" 2>/dev/null; then
    if ! htpasswd -Bbn "$USER_NAME" "$PASS_WORD" >"$tmp" 2>/dev/null; then
      echo "❌ htpasswd 產生 bcrypt 失敗（$service/$name）。" >&2
      exit 1
    fi
  fi
else
  echo "❌ 系統未提供 mkpasswd/htpasswd，無法產生 htpasswd（$service/$name）。" >&2
  echo "   - Debian/Ubuntu：sudo apt-get install -y whois（mkpasswd） 或 apache2-utils（htpasswd）" >&2
  echo "   - RHEL/CentOS：sudo dnf install -y whois（mkpasswd） 或 httpd-tools（htpasswd）" >&2
  exit 1
fi

chmod 600 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$htpasswd_path"
chmod 600 "$htpasswd_path" 2>/dev/null || true

trap - EXIT
rm -f "$tmp" 2>/dev/null || true
exit 0
