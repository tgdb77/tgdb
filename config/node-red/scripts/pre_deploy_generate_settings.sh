#!/usr/bin/env bash

# Node-RED 部署前初始化：依 auth.env 產生 settings.js 並預設啟用管理登入
#
# 說明：
# - 本腳本由 AppSpec `pre_deploy=` 呼叫（設定檔產生後、啟動單元前執行）
# - 會讀取 ${instance_dir}/auth.env 的帳號密碼，產生 ${instance_dir}/data/settings.js
# - 管理密碼會轉成 bcrypt 雜湊，不會以明文寫入 settings.js
#
# 參數：
#   $1 service（預設 node-red）
#   $2 name（container name）
#   $3 instance_dir
#   $4 host_port（未使用）

set -euo pipefail

service="${1:-node-red}"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
AUTH_ENV_PATH="$INSTANCE_DIR/auth.env"
TEMPLATE_PATH="$SERVICE_DIR/configs/settings.js.example"
SETTINGS_PATH="$INSTANCE_DIR/data/settings.js"

if [ ! -f "$AUTH_ENV_PATH" ]; then
  echo "❌ 找不到 auth.env：$AUTH_ENV_PATH（$service/$name）。" >&2
  exit 1
fi

if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "❌ 找不到 settings.js 範本：$TEMPLATE_PATH（$service/$name）。" >&2
  exit 1
fi

read_env_value() {
  local file="$1"
  local key="$2"

  [ -f "$file" ] || return 1

  awk -v k="$key" '
    /^[[:space:]]*#/ { next }
    index($0, "=") == 0 { next }
    {
      split($0, parts, "=")
      if (parts[1] == k) {
        sub(/^[^=]*=/, "", $0)
        sub(/\r$/, "", $0)
        print $0
        exit
      }
    }
  ' "$file"
}

USER_NAME="${user_name:-}"
PASS_WORD="${pass_word:-}"

if [ -z "${USER_NAME:-}" ]; then
  USER_NAME="$(read_env_value "$AUTH_ENV_PATH" "NODE_RED_ADMIN_USER" 2>/dev/null || true)"
fi
if [ -z "${PASS_WORD:-}" ]; then
  PASS_WORD="$(read_env_value "$AUTH_ENV_PATH" "NODE_RED_ADMIN_PASSWORD" 2>/dev/null || true)"
fi

if [ -z "${USER_NAME:-}" ]; then
  echo "❌ 缺少 Node-RED 管理帳號（$service/$name）。" >&2
  exit 1
fi
if [ -z "${PASS_WORD:-}" ]; then
  echo "❌ 缺少 Node-RED 管理密碼（$service/$name）。" >&2
  exit 1
fi
if [ "${#PASS_WORD}" -gt 72 ]; then
  echo "❌ Node-RED 管理密碼長度不可超過 72 字元（bcrypt 限制）：$AUTH_ENV_PATH（$service/$name）。" >&2
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

sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

PASS_HASH="$(generate_bcrypt_hash "$PASS_WORD")" || {
  echo "❌ 無法產生 Node-RED bcrypt 密碼雜湊（需要 mkpasswd 或 htpasswd）：$service/$name" >&2
  echo "   - Debian/Ubuntu：sudo apt-get install -y whois（mkpasswd）或 apache2-utils（htpasswd）" >&2
  echo "   - RHEL/CentOS：sudo dnf install -y whois（mkpasswd）或 httpd-tools（htpasswd）" >&2
  exit 1
}

mkdir -p "$(dirname "$SETTINGS_PATH")"

tmp="${SETTINGS_PATH}.tmp.$$"
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT

if ! sed \
  -e "s|__TGDB_NODE_RED_ADMIN_USER__|$(sed_escape "$USER_NAME")|g" \
  -e "s|__TGDB_NODE_RED_PASSWORD_HASH__|$(sed_escape "$PASS_HASH")|g" \
  "$TEMPLATE_PATH" >"$tmp"; then
  echo "❌ 產生 settings.js 失敗：$SETTINGS_PATH（$service/$name）。" >&2
  exit 1
fi

chmod 600 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$SETTINGS_PATH"
chmod 600 "$SETTINGS_PATH" 2>/dev/null || true

trap - EXIT
rm -f "$tmp" 2>/dev/null || true

echo "✅ 已產生 Node-RED 管理登入設定：$SETTINGS_PATH"
exit 0
