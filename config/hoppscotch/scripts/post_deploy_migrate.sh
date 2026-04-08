#!/bin/bash

set -euo pipefail

SERVICE="${1:-hoppscotch}"
NAME="${2:-}"
INSTANCE_DIR_ARG="${3:-}"

INSTANCE_DIR="${instance_dir:-${INSTANCE_DIR_ARG:-}}"
TIMEOUT="${HOPPSCOTCH_POST_DEPLOY_TIMEOUT:-120}"

if [ -z "$NAME" ]; then
  echo "❌ 找不到容器名稱，無法執行 Hoppscotch migration。($SERVICE)" >&2
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "❌ 系統未安裝 podman，無法執行 Hoppscotch migration。($SERVICE/$NAME)" >&2
  exit 1
fi

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ] 2>/dev/null; then
  TIMEOUT=120
fi

DB_USER="${HOPPSCOTCH_DB_USER:-${db_user:-hoppscotch}}"

echo "ℹ️ 正在等待 PostgreSQL 就緒後執行 Hoppscotch migration..."
if [ -n "$INSTANCE_DIR" ]; then
  echo "   - 實例目錄：$INSTANCE_DIR"
fi

container_is_running() {
  local container_name="$1"
  local running=""
  running="$(podman inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
  [ "$running" = "true" ]
}

wait_for_container_running() {
  local container_name="$1"
  local waited_local=0
  while [ "$waited_local" -lt "$TIMEOUT" ]; do
    if podman container exists "$container_name" >/dev/null 2>&1 && container_is_running "$container_name"; then
      return 0
    fi
    sleep 2
    waited_local=$((waited_local + 2))
  done
  return 1
}

waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if podman container exists "${NAME}-postgres" >/dev/null 2>&1 && \
     podman container exists "$NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

if ! podman container exists "${NAME}-postgres" >/dev/null 2>&1; then
  echo "❌ 等待 Hoppscotch PostgreSQL 容器建立逾時：${NAME}-postgres" >&2
  exit 1
fi

if ! podman container exists "$NAME" >/dev/null 2>&1; then
  echo "❌ 等待 Hoppscotch 容器建立逾時：$NAME" >&2
  exit 1
fi

if ! wait_for_container_running "${NAME}-postgres"; then
  echo "❌ 等待 Hoppscotch PostgreSQL 容器進入執行狀態逾時：${NAME}-postgres" >&2
  exit 1
fi

ready=0
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if podman exec "${NAME}-postgres" pg_isready -h 127.0.0.1 -p 5432 -U "$DB_USER" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

if [ "$ready" -ne 1 ]; then
  echo "❌ 等待 Hoppscotch PostgreSQL 就緒逾時，無法執行 migration。($SERVICE/$NAME)" >&2
  exit 1
fi

IMAGE_NAME="$(podman inspect -f '{{.ImageName}}' "$NAME" 2>/dev/null || true)"
if [ -z "$IMAGE_NAME" ]; then
  echo "❌ 無法取得 Hoppscotch 容器映像名稱：$NAME" >&2
  exit 1
fi

out=""
rc=0
out="$(podman run --rm \
  --pod "$NAME" \
  --env-file "${INSTANCE_DIR}/.env" \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" \
  -lc 'pnpm exec prisma migrate deploy' 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  out2=""
  rc2=0
  out2="$(podman run --rm \
    --pod "$NAME" \
    --env-file "${INSTANCE_DIR}/.env" \
    --entrypoint /bin/sh \
    "$IMAGE_NAME" \
    -lc 'pnpm dlx prisma migrate deploy' 2>&1)" || rc2=$?
  if [ "$rc2" -ne 0 ]; then
    echo "❌ Hoppscotch migration 執行失敗。($SERVICE/$NAME)" >&2
    [ -n "$out" ] && printf '%s\n' "$out" >&2
    [ -n "$out2" ] && printf '%s\n' "$out2" >&2
    exit 1
  fi
  out="$out2"
fi

echo "✅ Hoppscotch migration 已完成。"
[ -n "$out" ] && printf '%s\n' "$out"
