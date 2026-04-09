#!/usr/bin/env bash

# Gatus 部署前初始化：啟用 config.yaml 的 Basic Auth
#
# 說明：
# - 本腳本由 AppSpec `pre_deploy=` 呼叫（設定檔產生後、啟動單元前執行）
# - 會讀取輸入的 Basic Auth 帳號/密碼，將密碼轉成「bcrypt 後再 base64」
# - 再把結果寫入 ${instance_dir}/config/config.yaml

set -euo pipefail

service="${1:-gatus}"
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

CONFIG_PATH="$INSTANCE_DIR/config/config.yaml"
if [ ! -f "$CONFIG_PATH" ]; then
  echo "❌ 找不到 Gatus config.yaml：$CONFIG_PATH（$service/$name）。" >&2
  exit 1
fi

USER_NAME="${basic_auth_user:-${GATUS_BASIC_AUTH_USER:-}}"
PASS_WORD="${basic_auth_password:-${GATUS_BASIC_AUTH_PASSWORD:-}}"

if [ -z "${USER_NAME:-}" ]; then
  echo "❌ 缺少 Gatus Basic Auth 帳號（$service/$name）。" >&2
  exit 1
fi
if [ -z "${PASS_WORD:-}" ]; then
  echo "❌ 缺少 Gatus Basic Auth 密碼（$service/$name）。" >&2
  exit 1
fi
if [ "${#PASS_WORD}" -gt 72 ]; then
  echo "❌ Gatus Basic Auth 密碼長度不可超過 72 字元（bcrypt 限制）：$service/$name" >&2
  exit 1
fi

generate_bcrypt_hash() {
  local password="$1"
  local line hash

  if command -v mkpasswd >/dev/null 2>&1; then
    hash="$(printf '%s\n' "$password" | mkpasswd --method=bcrypt --stdin 2>/dev/null || true)"
    if [ -n "$hash" ]; then
      printf '%s\n' "$hash"
      return 0
    fi
  fi

  if command -v htpasswd >/dev/null 2>&1; then
    line="$(printf '%s\n' "$password" | htpasswd -Bni tgdb 2>/dev/null || true)"
    if [ -z "$line" ]; then
      line="$(htpasswd -Bbn tgdb "$password" 2>/dev/null || true)"
    fi
    if [ -n "$line" ]; then
      printf '%s\n' "${line#*:}"
      return 0
    fi
  fi

  return 1
}

base64_no_wrap() {
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w 0
  else
    base64 | tr -d '\n'
  fi
}

sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

PASS_HASH="$(generate_bcrypt_hash "$PASS_WORD")" || {
  echo "❌ 無法產生 Gatus bcrypt 密碼雜湊（需要 mkpasswd 或 htpasswd）：$service/$name" >&2
  echo "   - Debian/Ubuntu：sudo apt-get install -y whois（mkpasswd）或 apache2-utils（htpasswd）" >&2
  echo "   - RHEL/CentOS：sudo dnf install -y whois（mkpasswd）或 httpd-tools（htpasswd）" >&2
  exit 1
}

PASS_HASH_B64="$(printf '%s' "$PASS_HASH" | base64_no_wrap)"

tmp="${CONFIG_PATH}.tmp.$$"
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT

if ! sed \
  -e "s|__TGDB_GATUS_BASIC_AUTH_USER__|$(sed_escape "$USER_NAME")|g" \
  -e "s|__TGDB_GATUS_BASIC_AUTH_PASSWORD_BCRYPT_BASE64__|$(sed_escape "$PASS_HASH_B64")|g" \
  "$CONFIG_PATH" >"$tmp"; then
  echo "❌ 寫入 Gatus Basic Auth 設定失敗：$CONFIG_PATH（$service/$name）。" >&2
  exit 1
fi

chmod 600 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH" 2>/dev/null || true

trap - EXIT
rm -f "$tmp" 2>/dev/null || true

echo "✅ 已啟用 Gatus Basic Auth：$CONFIG_PATH"
exit 0
