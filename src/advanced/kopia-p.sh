#!/bin/bash

# Kopia 管理（Quadlet + 統一備份）入口
# 說明：本模組已依功能拆分至 src/advanced/kopia/。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_P_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_P_LOADED=1

KOPIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOPIA_MODULE_DIR="$KOPIA_DIR/kopia"
SRC_ROOT="$(cd "$KOPIA_DIR/.." && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"

# 需要復用 apps-p 的 Quadlet 部署核心（_deploy_app_core 等）
# shellcheck source=src/apps-p.sh
source "$SRC_ROOT/apps-p.sh"

# shellcheck source=src/advanced/kopia/kopia_menu_common.sh
source "$KOPIA_MODULE_DIR/kopia_menu_common.sh"
# shellcheck source=src/advanced/kopia/kopia_menu_repo.sh
source "$KOPIA_MODULE_DIR/kopia_menu_repo.sh"
# shellcheck source=src/advanced/kopia/kopia_menu_deploy.sh
source "$KOPIA_MODULE_DIR/kopia_menu_deploy.sh"
# shellcheck source=src/advanced/kopia/kopia_menu_remove.sh
source "$KOPIA_MODULE_DIR/kopia_menu_remove.sh"
# shellcheck source=src/advanced/kopia/kopia_menu_timers.sh
source "$KOPIA_MODULE_DIR/kopia_menu_timers.sh"
# shellcheck source=src/advanced/kopia/kopia_menu.sh
source "$KOPIA_MODULE_DIR/kopia_menu.sh"
