#!/usr/bin/env bash

set -euo pipefail

service="${1:-vaultwarden}"
name="${2:-}"
instance_dir_arg="${3:-}"

INSTANCE_DIR="${instance_dir:-${instance_dir_arg:-}}"
if [ -z "$INSTANCE_DIR" ] && [ -n "${TGDB_DIR:-}" ] && [ -n "${name:-}" ]; then
  INSTANCE_DIR="$TGDB_DIR/$name"
fi
if [ -z "$INSTANCE_DIR" ]; then
  echo "⚠️ 無法取得 instance_dir，略過顯示 ADMIN_TOKEN（$service/$name）。" >&2
  exit 0
fi

env_path="$INSTANCE_DIR/.env"
if [ ! -f "$env_path" ]; then
  echo "⚠️ 找不到 .env 檔案：$env_path（$service/$name）。" >&2
  exit 0
fi

token="$(grep -m1 '^ADMIN_TOKEN=' "$env_path" 2>/dev/null | sed 's/^ADMIN_TOKEN=//' | tr -d ' \t' || true)"

if [ -z "$token" ]; then
  echo "⚠️ 未找到 ADMIN_TOKEN（$service/$name）。" >&2
  exit 0
fi


echo "🔑 ADMIN_TOKEN : $token "


exit 0
