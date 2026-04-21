#!/usr/bin/env bash

set -euo pipefail

SERVICE="${1:-bookstack}"
NAME="${2:-}"
INSTANCE_DIR_ARG="${3:-}"
HOST_PORT_ARG="${4:-}"

INSTANCE_DIR="${instance_dir:-${INSTANCE_DIR_ARG:-}}"
HOST_PORT="${host_port:-${HOST_PORT_ARG:-}}"
ADMIN_EMAIL="${BOOKSTACK_ADMIN_EMAIL:-${admin_email:-}}"
ADMIN_PASSWORD="${BOOKSTACK_ADMIN_PASSWORD:-${admin_password:-${admin_pass:-}}}"
TIMEOUT="${BOOKSTACK_POST_DEPLOY_TIMEOUT:-120}"

if [ -z "$NAME" ]; then
  echo "❌ 找不到容器名稱，無法建立 BookStack 管理員。($SERVICE)" >&2
  exit 1
fi

if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ 缺少管理員 Email 或密碼，無法建立 BookStack 管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "❌ 系統未安裝 podman，無法建立 BookStack 管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ] 2>/dev/null; then
  TIMEOUT=120
fi

MAIN_CONTAINER="$NAME"
DB_CONTAINER="${NAME}-mariadb"

container_is_running() {
  local container_name="$1"
  local running=""
  running="$(podman inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
  [ "$running" = "true" ]
}

wait_for_running_container() {
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

bookstack_ready() {
  podman exec "$MAIN_CONTAINER" php /app/www/artisan list >/dev/null 2>&1
}

is_retryable_db_error() {
  local out="$1"
  printf '%s' "$out" | grep -Eqi \
    "SQLSTATE\\[HY000\\] \\[2002\\]|Connection refused|connection refused|Can't connect|cannot connect|server has gone away|No such file or directory"
}

is_missing_schema_error() {
  local out="$1"
  printf '%s' "$out" | grep -Eqi \
    "SQLSTATE\\[42S02\\]|Base table or view not found|doesn't exist|does not exist|Table '.*' doesn't exist"
}

run_migrations() {
  podman exec "$MAIN_CONTAINER" php /app/www/artisan migrate --force 2>&1
}

echo "ℹ️ 正在等待 BookStack 就緒後建立管理員..."
if [ -n "$INSTANCE_DIR" ]; then
  echo "   - 實例目錄：$INSTANCE_DIR"
fi
if [ -n "$HOST_PORT" ]; then
  echo "   - 登入位址：http://127.0.0.1:${HOST_PORT}/login"
fi

if ! wait_for_running_container "$MAIN_CONTAINER"; then
  if ! podman container exists "$MAIN_CONTAINER" >/dev/null 2>&1; then
    echo "❌ 等待 BookStack 容器建立逾時：$NAME" >&2
  else
    echo "❌ 等待 BookStack 容器進入執行狀態逾時：$NAME" >&2
  fi
  exit 1
fi

if ! wait_for_running_container "$DB_CONTAINER"; then
  if ! podman container exists "$DB_CONTAINER" >/dev/null 2>&1; then
    echo "❌ 等待 BookStack MariaDB 容器建立逾時：$DB_CONTAINER" >&2
  else
    echo "❌ 等待 BookStack MariaDB 容器進入執行狀態逾時：$DB_CONTAINER" >&2
  fi
  exit 1
fi

ready=0
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if bookstack_ready; then
    ready=1
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

if [ "$ready" -ne 1 ]; then
  echo "❌ 等待 BookStack 容器就緒逾時，無法建立管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

result=""
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  rc=0
  result="$(podman exec "$MAIN_CONTAINER" php /app/www/artisan bookstack:create-admin --initial --email="$ADMIN_EMAIL" --name="Admin" --password="$ADMIN_PASSWORD" 2>&1)" || rc=$?

  if [ "$rc" -eq 0 ]; then
    break
  fi

  if [ "$rc" -eq 2 ]; then
    echo "ℹ️ BookStack 已存在非初始管理員，略過 --initial 建立流程。"
    exit 0
  fi

  if is_missing_schema_error "$result"; then
    migrate_out=""
    migrate_rc=0
    migrate_out="$(run_migrations)" || migrate_rc=$?
    if [ "$migrate_rc" -eq 0 ]; then
      sleep 2
      waited=$((waited + 2))
      continue
    fi

    if is_retryable_db_error "$migrate_out" || is_missing_schema_error "$migrate_out"; then
      sleep 2
      waited=$((waited + 2))
      continue
    fi

    echo "❌ 執行 BookStack migration 失敗。($SERVICE/$NAME)" >&2
    [ -n "$migrate_out" ] && printf '%s\n' "$migrate_out" >&2
    exit 1
  fi

  if is_retryable_db_error "$result"; then
    sleep 2
    waited=$((waited + 2))
    continue
  fi

  echo "❌ 建立 BookStack 管理員失敗。($SERVICE/$NAME)" >&2
  printf '%s\n' "$result" >&2
  exit 1
done

if [ "${rc:-1}" -ne 0 ]; then
  echo "❌ 等待 BookStack 資料庫就緒逾時，無法建立管理員。($SERVICE/$NAME)" >&2
  [ -n "$result" ] && printf '%s\n' "$result" >&2
  exit 1
fi

echo "✅ 已完成 BookStack 初始管理員設定：$ADMIN_EMAIL"
[ -n "$result" ] && printf '%s\n' "$result"
