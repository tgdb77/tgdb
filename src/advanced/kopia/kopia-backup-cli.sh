#!/bin/bash

# Kopia 統一備份 CLI 正式入口
# 說明：實作位於 src/advanced/kopia/ 子模組。

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

KOPIA_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/advanced/kopia/kopia-backup-loader.sh
source "$KOPIA_CLI_DIR/kopia-backup-loader.sh"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

if kopia_backup_main "$@"; then
  exit 0
else
  exit $?
fi
