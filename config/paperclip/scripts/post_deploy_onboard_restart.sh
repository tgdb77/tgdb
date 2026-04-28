#!/usr/bin/env bash

set -euo pipefail

SERVICE="${1:-paperclip}"
NAME="${2:-}"
INSTANCE_DIR_ARG="${3:-}"
HOST_PORT_ARG="${4:-}"

INSTANCE_DIR="${instance_dir:-${INSTANCE_DIR_ARG:-}}"
HOST_PORT="${host_port:-${HOST_PORT_ARG:-}}"
TIMEOUT="${PAPERCLIP_POST_DEPLOY_TIMEOUT:-180}"

CONFIG_RELATIVE_PATH="instances/default/config.json"
CONFIG_HOST_PATH="${INSTANCE_DIR}/data/${CONFIG_RELATIVE_PATH}"

if [ -z "$NAME" ]; then
  echo "❌ 找不到 Paperclip 容器名稱，無法執行自動 onboard。($SERVICE)" >&2
  exit 1
fi

if [ -z "$INSTANCE_DIR" ]; then
  echo "❌ 找不到 Paperclip instance_dir，無法執行自動 onboard。($SERVICE/$NAME)" >&2
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "❌ 系統未安裝 podman，無法執行 Paperclip 自動 onboard。($SERVICE/$NAME)" >&2
  exit 1
fi

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ] 2>/dev/null; then
  TIMEOUT=180
fi

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

resolve_systemctl_scope() {
  if [ "${TGDB_APPS_ACTIVE_SCOPE:-}" = "system" ]; then
    printf '%s\n' "system"
    return 0
  fi

  case "${TGDB_APPS_ACTIVE_DEPLOY_MODE:-rootless}" in
    rootful)
      printf '%s\n' "system"
      ;;
    *)
      printf '%s\n' "user"
      ;;
  esac
}

restart_managed_container() {
  local scope unit
  scope="$(resolve_systemctl_scope)"

  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi

  local -a candidates=(
    "${NAME}.container"
    "${NAME}.service"
    "container-${NAME}.service"
  )

  case "$scope" in
    system)
      for unit in "${candidates[@]}"; do
        if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
          systemctl restart -- "$unit" >/dev/null 2>&1 && return 0
        elif command -v sudo >/dev/null 2>&1; then
          sudo systemctl restart -- "$unit" >/dev/null 2>&1 && return 0
        fi
      done
      ;;
    *)
      for unit in "${candidates[@]}"; do
        systemctl --user restart -- "$unit" >/dev/null 2>&1 && return 0
      done
      ;;
  esac

  return 1
}

prepare_instance_permissions() {
  podman exec "$NAME" sh -lc '
    mkdir -p /paperclip/instances/default
    chown -R node:node /paperclip/instances/default
  '
}

run_onboard_inside_container() {
  podman exec --user node "$NAME" sh -lc '
    cd /app
    node --import ./server/node_modules/tsx/dist/loader.mjs --input-type=module -e '"'"'
      const mod = await import("./cli/src/commands/onboard.ts");
      await mod.onboard({ yes: true, invokedByRun: true, bind: "lan" });
    '"'"'
  '
}

echo "ℹ️ 正在檢查 Paperclip 初始化狀態..."
if [ -n "$HOST_PORT" ]; then
  echo "   - Web UI：http://127.0.0.1:${HOST_PORT}"
fi
echo "   - 設定檔：$CONFIG_HOST_PATH"

if ! wait_for_running_container "$NAME"; then
  echo "❌ 等待 Paperclip 容器進入執行狀態逾時：$NAME" >&2
  exit 1
fi

if [ -s "$CONFIG_HOST_PATH" ]; then
  echo "ℹ️ 已偵測到既有 Paperclip 設定檔，略過自動 onboard。"
  exit 0
fi

echo "⏳ 尚未找到 Paperclip 設定檔，正在準備 instance 權限..."
if ! prepare_instance_permissions >/dev/null 2>&1; then
  echo "⚠️ 無法預先校正 Paperclip instance 權限，將直接嘗試 onboard。" >&2
fi

echo "⏳ 正在容器內自動執行 Paperclip onboard..."
onboard_output=""
if ! onboard_output="$(run_onboard_inside_container 2>&1)"; then
  echo "❌ Paperclip 自動 onboard 失敗。($SERVICE/$NAME)" >&2
  printf '%s\n' "$onboard_output" >&2
  exit 1
fi
printf '%s\n' "$onboard_output"

if [ ! -s "$CONFIG_HOST_PATH" ]; then
  echo "❌ onboard 執行後仍找不到設定檔：$CONFIG_HOST_PATH" >&2
  exit 1
fi

echo "ℹ️ 正在透過 systemd/Quadlet 重新啟動 Paperclip，讓新設定生效..."
if ! restart_managed_container; then
  echo "❌ 無法透過 systemd/Quadlet 自動重啟 Paperclip。($SERVICE/$NAME)" >&2
  echo "   - 請手動執行：systemctl --user restart ${NAME}.service" >&2
  exit 1
fi

if ! wait_for_running_container "$NAME"; then
  echo "❌ Paperclip 重啟後未能在 ${TIMEOUT} 秒內恢復執行：$NAME" >&2
  exit 1
fi

echo "✅ 已完成 Paperclip onboard，並自動重啟服務。"
