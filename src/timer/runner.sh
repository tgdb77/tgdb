#!/bin/bash

# TGDB 定時任務：統一執行入口
# 注意：此檔案可被 source，也可直接執行。

if [ -n "${_TGDB_TIMER_RUNNER_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
  fi
fi
_TGDB_TIMER_RUNNER_LOADED=1

tgdb_timer_runner_init_context() {
  if [ -n "${TGDB_DIR:-}" ]; then
    return 0
  fi

  if declare -F load_system_config >/dev/null 2>&1; then
    load_system_config || true
  fi
}

tgdb_timer_runner_script_path() {
  if [ -n "${TGDB_REPO_DIR:-}" ]; then
    printf '%s\n' "$TGDB_REPO_DIR/src/timer/runner.sh"
    return 0
  fi

  printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/runner.sh"
}

tgdb_timer_run_via_runner() {
  local task_id="$1"
  local origin="${2:-manual}"
  local runner_path

  runner_path="$(tgdb_timer_runner_script_path)"
  /bin/bash "$runner_path" run "$task_id" "$origin"
}

tgdb_timer_runner_execute() {
  local task_id="$1"
  local origin="${2:-timer}"
  local rc=0

  tgdb_timer_runner_init_context
  tgdb_timer_registry_load_task "$task_id" || return 1

  if tgdb_timer_healthchecks_should_notify "$task_id" "$origin"; then
    tgdb_timer_healthchecks_send "$task_id" "start" "0" || true
  fi

  if [ -n "${TGDB_TIMER_RUN_NOW_CB:-}" ]; then
    tgdb_timer_call_callback "$TGDB_TIMER_RUN_NOW_CB" || rc=$?
  else
    tgdb_fail "此任務未定義立即執行回呼：$task_id" 1 || return $?
  fi

  if tgdb_timer_healthchecks_should_notify "$task_id" "$origin"; then
    if [ "$rc" -eq 0 ]; then
      tgdb_timer_healthchecks_send "$task_id" "success" "$rc" || true
    else
      tgdb_timer_healthchecks_send "$task_id" "fail" "$rc" || true
    fi
  fi

  return "$rc"
}

tgdb_timer_runner_main() {
  local subcmd="${1:-}"

  case "$subcmd" in
    run)
      shift || true
      if [ -z "${1:-}" ]; then
        tgdb_fail "用法：timer/runner.sh run <task_id> [timer|manual]" 2 || return $?
      fi
      tgdb_timer_runner_execute "$1" "${2:-timer}"
      ;;
    *)
      tgdb_fail "用法：timer/runner.sh run <task_id> [timer|manual]" 2 || return $?
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail

  TIMER_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=src/core/bootstrap.sh
  source "$TIMER_RUNNER_DIR/../core/bootstrap.sh"

  tgdb_timer_runner_main "$@" || exit $?
fi
