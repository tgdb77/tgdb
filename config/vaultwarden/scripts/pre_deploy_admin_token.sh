#!/usr/bin/env bash

# Vaultwarden 部署前初始化：自動產生 ADMIN_TOKEN

set -euo pipefail

service="${1:-vaultwarden}"
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

env_path="$INSTANCE_DIR/.env"
if [ ! -f "$env_path" ]; then
  echo "❌ 找不到 .env：$env_path（$service/$name）。" >&2
  exit 1
fi

# 檢查是否已存在有效的 ADMIN_TOKEN
current="$(grep -m1 '^ADMIN_TOKEN=' "$env_path" 2>/dev/null | sed 's/^ADMIN_TOKEN=//' | tr -d ' \t' || true)"
if [ -n "$current" ]; then
  echo "✅ ADMIN_TOKEN 已存在，跳過產生（$service/$name）。"
  exit 0
fi

# 產生 ADMIN_TOKEN（官方推薦方式）
if ! command -v openssl >/dev/null 2>&1; then
  echo "❌ 需要 openssl 才能產生 ADMIN_TOKEN，請先安裝（$service/$name）。" >&2
  echo "   sudo apt-get install -y openssl" >&2
  exit 1
fi

token="$(openssl rand -base64 32 2>/dev/null | tr -d '\n' || true)"

if [ -z "$token" ]; then
  echo "❌ 無法產生 ADMIN_TOKEN（$service/$name）。" >&2
  exit 1
fi

# 更新 .env 檔案
tmp="${env_path}.tmp.$$"
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT

awk -v v="$token" '
  BEGIN { done=0 }
  /^ADMIN_TOKEN=/ {
    if (done == 0) {
      print "ADMIN_TOKEN=" v
      done=1
      next
    }
  }
  { print }
  END {
    if (done == 0) {
      print "ADMIN_TOKEN=" v
    }
  }
' "$env_path" > "$tmp"

chmod 600 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$env_path"
chmod 600 "$env_path" 2>/dev/null || true

trap - EXIT
rm -f "$tmp" 2>/dev/null || true
