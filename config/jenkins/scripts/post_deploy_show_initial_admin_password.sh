#!/bin/bash

set -euo pipefail

SERVICE="${1:-jenkins}"
NAME="${2:-}"
INSTANCE_DIR_ARG="${3:-}"
HOST_PORT_ARG="${4:-}"

INSTANCE_DIR="${instance_dir:-${INSTANCE_DIR_ARG:-}}"
HOST_PORT="${host_port:-${HOST_PORT_ARG:-}}"
TIMEOUT="${JENKINS_INITIAL_ADMIN_PASSWORD_TIMEOUT:-180}"

if [ -z "$INSTANCE_DIR" ]; then
  echo "⚠️ 找不到 Jenkins instance_dir，無法顯示初始管理員密碼。($SERVICE/$NAME)" >&2
  exit 0
fi

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ] 2>/dev/null; then
  TIMEOUT=180
fi

PASSWORD_FILE="$INSTANCE_DIR/jenkins_home/secrets/initialAdminPassword"

echo "ℹ️ 正在等待 Jenkins 產生初始管理員密碼..."
if [ -n "$HOST_PORT" ]; then
  echo "   - Jenkins Web UI：http://127.0.0.1:${HOST_PORT}"
fi
echo "   - 密碼檔案：$PASSWORD_FILE"

waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if [ -s "$PASSWORD_FILE" ]; then
    PASSWORD="$(head -n 1 "$PASSWORD_FILE" 2>/dev/null || true)"
    if [ -n "$PASSWORD" ]; then
      echo "🔐 Jenkins 初始管理員密碼：$PASSWORD"
      exit 0
    fi
  fi
  sleep 2
  waited=$((waited + 2))
done

echo "⚠️ 在 ${TIMEOUT} 秒內尚未取得 Jenkins 初始管理員密碼，請稍後手動查看：" >&2
echo "   ${PASSWORD_FILE}" >&2
exit 0
