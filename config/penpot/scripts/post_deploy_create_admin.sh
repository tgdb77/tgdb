#!/bin/bash

set -euo pipefail

SERVICE="${1:-penpot}"
NAME="${2:-}"
INSTANCE_DIR_ARG="${3:-}"
HOST_PORT_ARG="${4:-}"

INSTANCE_DIR="${instance_dir:-${INSTANCE_DIR_ARG:-}}"
HOST_PORT="${host_port:-${HOST_PORT_ARG:-}}"

ADMIN_NAME="${PENPOT_ADMIN_NAME:-${admin_name:-}}"
ADMIN_EMAIL="${PENPOT_ADMIN_EMAIL:-${admin_email:-}}"
ADMIN_PASSWORD="${PENPOT_ADMIN_PASSWORD:-${admin_password:-}}"

TIMEOUT="${PENPOT_POST_DEPLOY_TIMEOUT:-120}"

if [ -z "$NAME" ]; then
  echo "❌ 找不到容器名稱，無法建立 Penpot 初始管理員。($SERVICE)" >&2
  exit 1
fi

if [ -z "$ADMIN_NAME" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ 缺少初始管理員資訊，無法建立 Penpot 初始管理員。($SERVICE/$NAME)" >&2
  echo "   - ADMIN_NAME/ADMIN_EMAIL/ADMIN_PASSWORD 不得為空" >&2
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "❌ 系統未安裝 podman，無法建立 Penpot 初始管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

BACKEND="${NAME}-backend"

if ! podman container exists "$BACKEND" >/dev/null 2>&1; then
  echo "❌ 找不到 Penpot backend 容器：$BACKEND" >&2
  exit 1
fi

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ] 2>/dev/null; then
  TIMEOUT=120
fi

run_create_profile() {
  # 參考：Penpot 官方建議在 backend 容器內使用 manage.py create-profile 建立初始使用者。
  # - 若已存在同 Email 的使用者，Penpot 可能回傳錯誤訊息；此腳本會視訊息做容錯處理。
  podman exec "$BACKEND" \
    python3 manage.py create-profile \
    -n "$ADMIN_NAME" \
    -e "$ADMIN_EMAIL" \
    -p "$ADMIN_PASSWORD" \
    --skip-tutorial \
    --skip-walkthrough 2>&1
}

echo "ℹ️ 正在等待 Penpot 就緒後建立初始管理員..."
if [ -n "$INSTANCE_DIR" ]; then
  echo "   - 實例目錄：$INSTANCE_DIR"
fi
if [ -n "$HOST_PORT" ]; then
  echo "   - Web UI：http://127.0.0.1:${HOST_PORT}"
fi
echo "   - 管理員 Email：$ADMIN_EMAIL"

ready=0
waited=0
last_out=""
while [ "$waited" -lt "$TIMEOUT" ]; do
  out=""
  rc=0
  out="$(run_create_profile)" || rc=$?
  last_out="$out"

  if [ "$rc" -eq 0 ]; then
    ready=1
    break
  fi

  # 常見：已存在同 Email 使用者（視為成功，避免重跑卡住）
  if printf '%s' "$out" | grep -Eqi "already exists|exists already|duplicate|conflict|email.*exists"; then
    echo "✅ 已存在同 Email 的 Penpot 使用者，略過建立：$ADMIN_EMAIL"
    return 0
  fi

  # 常見：服務尚未就緒（DB migration / prepl server 未 ready）
  if printf '%s' "$out" | grep -Eqi "connection refused|ECONNREFUSED|timeout|timed out|prepl|not ready|cannot connect|failed to connect"; then
    sleep 2
    waited=$((waited + 2))
    continue
  fi

  # 其他錯誤：直接中止
  echo "❌ 建立 Penpot 初始管理員失敗。($SERVICE/$NAME)" >&2
  printf '%s\n' "$out" >&2
  exit 1
done

if [ "$ready" -ne 1 ]; then
  echo "❌ 等待 Penpot 就緒逾時，無法建立初始管理員。($SERVICE/$NAME)" >&2
  [ -n "$last_out" ] && printf '%s\n' "$last_out" >&2
  exit 1
fi

echo "✅ 已建立 Penpot 初始管理員：$ADMIN_EMAIL"
