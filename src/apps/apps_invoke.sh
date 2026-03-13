#!/bin/bash

# Apps：AppSpec 動作呼叫/判斷（由 src/apps-p.sh 載入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_env_key_is_valid() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

_app_invoke() {
  local service="$1" action="$2"
  shift 2

  if appspec_has_service "$service" && appspec_can_handle "$service" "$action"; then
    appspec_invoke "$service" "$action" "$@"
    return $?
  fi

  tgdb_fail "服務 '$service' 尚未支援動作 '$action'" 1 || return $?
}

_app_fn_exists() {
  local service="$1" action="$2"
  appspec_has_service "$service" && appspec_can_handle "$service" "$action"
}

_app_is_aux_instance_name() {
  local service="$1" name="$2"
  if _app_fn_exists "$service" is_aux_instance_name; then
    _app_invoke "$service" is_aux_instance_name "$name"
    return $?
  fi
  return 1
}
