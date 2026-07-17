#!/bin/bash

# Headscale / Tailscale / DERP 管理入口
# 說明：功能實作已拆分至 src/advanced/headscale/。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_HEADSCALE_P_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_HEADSCALE_P_LOADED=1

HEADSCALE_P_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADSCALE_MODULE_DIR="$HEADSCALE_P_DIR/headscale"

# shellcheck source=src/advanced/headscale/core.sh
source "$HEADSCALE_MODULE_DIR/core.sh"
# shellcheck source=src/advanced/headscale/tailscale.sh
source "$HEADSCALE_MODULE_DIR/tailscale.sh"
# shellcheck source=src/advanced/headscale/derper.sh
source "$HEADSCALE_MODULE_DIR/derper.sh"
