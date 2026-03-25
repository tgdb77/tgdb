#!/bin/bash

# 應用部署（Quadlet，rootless）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_LIB_DIR="$SCRIPT_DIR/apps"

# shellcheck source=src/core/bootstrap.sh
source "$SCRIPT_DIR/core/bootstrap.sh"

# shellcheck source=src/core/quadlet_common.sh
source "$SCRIPT_DIR/core/quadlet_common.sh"

# shellcheck source=src/apps/app_spec.sh
source "$APPS_LIB_DIR/app_spec.sh"

# shellcheck source=src/apps/apps_scope.sh
source "$APPS_LIB_DIR/apps_scope.sh"

# shellcheck source=src/apps/app_spec_exec.sh
source "$APPS_LIB_DIR/app_spec_exec.sh"

# shellcheck source=src/apps/apps_invoke.sh
source "$APPS_LIB_DIR/apps_invoke.sh"
# shellcheck source=src/apps/apps_services.sh
source "$APPS_LIB_DIR/apps_services.sh"
# shellcheck source=src/apps/apps_podman.sh
source "$APPS_LIB_DIR/apps_podman.sh"
# shellcheck source=src/apps/apps_quadlet.sh
source "$APPS_LIB_DIR/apps_quadlet.sh"
# shellcheck source=src/apps/apps_deploy.sh
source "$APPS_LIB_DIR/apps_deploy.sh"
# shellcheck source=src/apps/apps_records.sh
source "$APPS_LIB_DIR/apps_records.sh"
# shellcheck source=src/apps/apps_manage.sh
source "$APPS_LIB_DIR/apps_manage.sh"
# shellcheck source=src/apps/apps_menu.sh
source "$APPS_LIB_DIR/apps_menu.sh"
