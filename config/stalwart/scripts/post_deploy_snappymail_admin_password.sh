#!/bin/bash

set -euo pipefail

SERVICE="${1:-stalwart}"
NAME="${2:-}"
INSTANCE_DIR_ARG="${3:-}"

INSTANCE_DIR="${instance_dir:-${INSTANCE_DIR_ARG:-}}"
if [ -z "$INSTANCE_DIR" ] && [ -n "${TGDB_DIR:-}" ] && [ -n "$NAME" ]; then
  INSTANCE_DIR="$TGDB_DIR/$NAME"
fi

TIMEOUT="${SNAPPYMAIL_POST_DEPLOY_TIMEOUT:-90}"
if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ] 2>/dev/null; then
  TIMEOUT=90
fi

if [ -z "$NAME" ]; then
  echo "❌ 找不到實例名稱，無法設定 SnappyMail Webmail 管理密碼。($SERVICE)" >&2
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "❌ 系統未安裝 podman，無法設定 SnappyMail Webmail 管理密碼。($SERVICE/$NAME)" >&2
  exit 1
fi

CONTAINER="${NAME}-snappymail"
PW_PATH="/var/lib/snappymail/_data_/_default_/admin_password.txt"

echo "ℹ️ 正在初始化 SnappyMail Webmail 管理密碼..."
if [ -n "$INSTANCE_DIR" ]; then
  echo "   - 實例目錄：$INSTANCE_DIR"
fi

ready=0
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if podman container exists "$CONTAINER" >/dev/null 2>&1; then
    running="$(podman inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)"
    if [ "$running" = "true" ]; then
      ready=1
      break
    fi
  fi
  sleep 2
  waited=$((waited + 2))
done

if [ "$ready" -ne 1 ]; then
  echo "❌ 等待 SnappyMail 容器就緒逾時，無法取得 Webmail 管理密碼：$CONTAINER ($SERVICE/$NAME)" >&2
  exit 1
fi

_snappymail_read_password() {
  podman exec "$CONTAINER" sh -lc "test -s '$PW_PATH' && head -n 1 '$PW_PATH' | sed 's/\\r$//'" 2>/dev/null || true
}

waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  webmail_pw="$(_snappymail_read_password)"
  if [ -n "$webmail_pw" ]; then
    echo "🔐 Webmail 管理帳號：admin"
    echo "🔐 Webmail 管理密碼：$webmail_pw"
    exit 0
  fi

  sleep 2
  waited=$((waited + 2))
done

echo "⚠️ 尚未取得 Webmail 管理密碼（可能尚未完成初始化）。" >&2
if [ -n "$INSTANCE_DIR" ]; then
  echo "   - 請稍後查看：$INSTANCE_DIR/snappymail/_data_/_default_/admin_password.txt" >&2
else
  echo "   - 請稍後查看：$PW_PATH（容器內路徑；可用 podman exec $CONTAINER cat $PW_PATH）" >&2
fi

exit 0
