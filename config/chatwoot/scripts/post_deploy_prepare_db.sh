#!/bin/bash

# Chatwoot：部署後初始化資料庫（可選）
#
# - 預設會執行（由 .env 控制 CHATWOOT_AUTO_PREPARE_DB=1）
# - 只在第一次執行成功後寫入 marker，避免每次重啟都跑 migration
#
# 參數：$1=service $2=name $3=instance_dir $4=host_port

service="${1:-}"
name="${2:-}"
instance_dir="${3:-}"
host_port="${4:-}"

_truthy() {
  local v="${1:-}"
  case "${v,,}" in
    1|true|yes|y) return 0 ;;
  esac
  return 1
}

if ! _truthy "${CHATWOOT_AUTO_PREPARE_DB:-1}"; then
  exit 0
fi

marker="$instance_dir/.chatwoot_prepare_db.done"
if [ -f "$marker" ] && ! _truthy "${CHATWOOT_AUTO_PREPARE_DB_FORCE:-0}"; then
  exit 0
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "⚠️ 找不到 podman，無法自動執行 db:chatwoot_prepare。" >&2
  exit 0
fi

container="${container_name:-$name}"
if [ -z "$container" ]; then
  echo "⚠️ 找不到容器名稱，略過 db:chatwoot_prepare（service=$service）。" >&2
  exit 0
fi

echo "=== Chatwoot：嘗試初始化資料庫（db:chatwoot_prepare） ===" >&2
echo "service=$service name=$name container=$container host_port=$host_port" >&2

# 等待容器就緒（最多 90 秒）
running=""
for ((i = 1; i <= 90; i++)); do
  running="$(podman inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)"
  if [ "$running" = "true" ]; then
    break
  fi
  sleep 1
done

if [ "$running" != "true" ]; then
  echo "⚠️ 容器尚未就緒，略過 db:chatwoot_prepare。你可稍後手動執行：" >&2
  echo "   podman exec -it $container sh -lc 'bundle exec rails db:chatwoot_prepare'" >&2
  exit 0
fi

timeout_secs="${CHATWOOT_AUTO_PREPARE_DB_TIMEOUT:-180}"
if [[ ! "$timeout_secs" =~ ^[0-9]+$ ]] || [ "$timeout_secs" -le 0 ] 2>/dev/null; then
  timeout_secs=180
fi

rc=0
out=""
if command -v timeout >/dev/null 2>&1; then
  out="$(timeout "${timeout_secs}s" podman exec "$container" sh -lc 'bundle exec rails db:chatwoot_prepare' 2>&1)" || rc=$?
else
  out="$(podman exec "$container" sh -lc 'bundle exec rails db:chatwoot_prepare' 2>&1)" || rc=$?
fi

printf '%s\n' "$out"

if [ "$rc" -ne 0 ]; then
  if [ "$rc" -eq 124 ]; then
    echo "⚠️ db:chatwoot_prepare 執行逾時（${timeout_secs}s），已略過（allow_fail=1）。" >&2
  else
    echo "⚠️ db:chatwoot_prepare 執行失敗（rc=$rc），已略過（allow_fail=1）。" >&2
  fi
  exit 0
fi

date '+%F %T' >"$marker" 2>/dev/null || true
echo "✅ 已完成 db:chatwoot_prepare（marker：$marker）" >&2
exit 0
