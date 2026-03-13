#!/bin/bash

# Kopia 備份 CLI：模組載入入口
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_BACKUP_LOADER_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_BACKUP_LOADER_LOADED=1

KOPIA_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOPIA_DIR="$(cd "$KOPIA_MODULE_DIR/.." && pwd)"
SRC_ROOT="$(cd "$KOPIA_DIR/.." && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

# shellcheck source=src/advanced/kopia/kopia_backup_core.sh
source "$KOPIA_MODULE_DIR/kopia_backup_core.sh"
# shellcheck source=src/advanced/kopia/kopia_backup_scan.sh
source "$KOPIA_MODULE_DIR/kopia_backup_scan.sh"
# shellcheck source=src/advanced/kopia/kopia_backup_prepare.sh
source "$KOPIA_MODULE_DIR/kopia_backup_prepare.sh"
# shellcheck source=src/advanced/kopia/kopia_backup_restore_lib.sh
source "$KOPIA_MODULE_DIR/kopia_backup_restore_lib.sh"
# shellcheck source=src/advanced/kopia/kopia_backup_run.sh
source "$KOPIA_MODULE_DIR/kopia_backup_run.sh"
# shellcheck source=src/advanced/kopia/kopia_backup_cmd.sh
source "$KOPIA_MODULE_DIR/kopia_backup_cmd.sh"
