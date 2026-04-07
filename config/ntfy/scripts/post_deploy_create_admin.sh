#!/bin/bash

set -euo pipefail

SERVICE="${1:-ntfy}"
NAME="${2:-}"
INSTANCE_DIR_ARG="${3:-}"
HOST_PORT_ARG="${4:-}"

INSTANCE_DIR="${instance_dir:-${INSTANCE_DIR_ARG:-}}"
HOST_PORT="${host_port:-${HOST_PORT_ARG:-}}"

ADMIN_USER="${NTFY_ADMIN_USER:-${admin_user:-}}"
ADMIN_PASS="${NTFY_ADMIN_PASS:-${admin_pass:-}}"

TIMEOUT="${NTFY_POST_DEPLOY_TIMEOUT:-120}"

if [ -z "$NAME" ]; then
  echo "❌ 找不到容器名稱，無法建立 ntfy 管理員。($SERVICE)" >&2
  exit 1
fi

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
  echo "❌ 缺少管理員帳號或密碼，無法建立 ntfy 管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "❌ 系統未安裝 podman，無法建立 ntfy 管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

if ! podman container exists "$NAME" >/dev/null 2>&1; then
  echo "❌ 找不到 ntfy 容器：$NAME" >&2
  exit 1
fi

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ] 2>/dev/null; then
  TIMEOUT=120
fi

echo "ℹ️ 正在等待 ntfy 就緒後建立管理員..."
if [ -n "$INSTANCE_DIR" ]; then
  echo "   - 實例目錄：$INSTANCE_DIR"
fi
if [ -n "$HOST_PORT" ]; then
  echo "   - Web UI：http://127.0.0.1:${HOST_PORT}"
fi
echo "   - 管理員帳號：$ADMIN_USER"

ready=0
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if command -v curl >/dev/null 2>&1 && [ -n "$HOST_PORT" ]; then
    if curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:${HOST_PORT}/v1/health" 2>/dev/null; then
      ready=1
      break
    fi
  else
    # 後備：只要容器能跑 user 子命令，通常代表檔案/權限也就緒
    if podman exec "$NAME" ntfy --help >/dev/null 2>&1; then
      ready=1
      break
    fi
  fi
  sleep 2
  waited=$((waited + 2))
done

if [ "$ready" -ne 1 ]; then
  echo "❌ 等待 ntfy 就緒逾時，無法建立管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

# ntfy user add 通常會要求輸入密碼；此處優先用 NTFY_PASSWORD 非互動式建立。
# 若版本不支援，則回退到 stdin 方式。
out=""
rc=0
out="$(podman exec -e "NTFY_PASSWORD=$ADMIN_PASS" "$NAME" ntfy user add --role=admin "$ADMIN_USER" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  out2=""
  rc2=0
  out2="$(printf '%s\n%s\n' "$ADMIN_PASS" "$ADMIN_PASS" | podman exec -i "$NAME" ntfy user add --role=admin "$ADMIN_USER" 2>&1)" || rc2=$?
  if [ "$rc2" -ne 0 ]; then
    # 已存在使用者：視為成功（避免重跑卡住）
    if printf '%s\n%s\n' "$out" "$out2" | grep -Eqi "already exists|exists already|duplicate|conflict"; then
      echo "✅ 已存在同名 ntfy 使用者，略過建立：$ADMIN_USER"
      exit 0
    fi
    echo "❌ 建立 ntfy 管理員失敗。($SERVICE/$NAME)" >&2
    [ -n "$out" ] && printf '%s\n' "$out" >&2
    [ -n "$out2" ] && printf '%s\n' "$out2" >&2
    exit 1
  fi
  out="$out2"
fi

echo "✅ 已建立 ntfy 管理員：$ADMIN_USER"

