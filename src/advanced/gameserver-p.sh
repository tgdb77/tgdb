#!/bin/bash

# Game Server（LinuxGSM / docker-gameserver）管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_GAMESERVER_P_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_GAMESERVER_P_LOADED=1

GAMESERVER_P_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$GAMESERVER_P_DIR/.." && pwd)"
GAMESERVER_MODULE_DIR="$GAMESERVER_P_DIR/gameserver"

# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

# shellcheck source=src/advanced/gameserver/common.sh
source "$GAMESERVER_MODULE_DIR/common.sh"
# shellcheck source=src/advanced/gameserver/deploy.sh
source "$GAMESERVER_MODULE_DIR/deploy.sh"
# shellcheck source=src/advanced/gameserver/manage.sh
source "$GAMESERVER_MODULE_DIR/manage.sh"
# shellcheck source=src/advanced/gameserver/menu.sh
source "$GAMESERVER_MODULE_DIR/menu.sh"

