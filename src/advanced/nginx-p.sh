#!/bin/bash

# Nginx（Podman + Quadlet）管理模組（入口）
# 說明：已依功能拆分至 src/advanced/nginx/。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_NGINX_P_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_NGINX_P_LOADED=1

NGINX_P_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$NGINX_P_SCRIPT_DIR/../core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$NGINX_P_SCRIPT_DIR/../core/quadlet_common.sh"

# shellcheck source=src/advanced/nginx/nginx_menu.sh
source "$NGINX_P_SCRIPT_DIR/nginx/nginx_menu.sh"
