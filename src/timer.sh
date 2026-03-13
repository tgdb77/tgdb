#!/bin/bash

# 定時任務統一管理入口
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_TIMER_P_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_TIMER_P_LOADED=1

TIMER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$TIMER_DIR/core/bootstrap.sh"

# shellcheck source=src/timer/common.sh
[ -f "$TIMER_DIR/timer/common.sh" ] && source "$TIMER_DIR/timer/common.sh"
# shellcheck source=src/timer/registry.sh
[ -f "$TIMER_DIR/timer/registry.sh" ] && source "$TIMER_DIR/timer/registry.sh"
# shellcheck source=src/timer/custom.sh
[ -f "$TIMER_DIR/timer/custom.sh" ] && source "$TIMER_DIR/timer/custom.sh"
# shellcheck source=src/timer/healthchecks.sh
[ -f "$TIMER_DIR/timer/healthchecks.sh" ] && source "$TIMER_DIR/timer/healthchecks.sh"
# shellcheck source=src/timer/runner.sh
[ -f "$TIMER_DIR/timer/runner.sh" ] && source "$TIMER_DIR/timer/runner.sh"
# shellcheck source=src/timer/menu.sh
[ -f "$TIMER_DIR/timer/menu.sh" ] && source "$TIMER_DIR/timer/menu.sh"
