#!/bin/bash

# 數據庫備份：批次 CLI 正式入口
# 說明：統一由 dbadmin-p.sh 載入模組並轉發至 dbbackup_all_main。
# 注意：本檔案可能被 systemd timer 直接執行。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

DBADMIN_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/advanced/dbadmin-p.sh
source "$DBADMIN_CLI_DIR/../dbadmin-p.sh"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

if dbbackup_all_main "$@"; then
  exit 0
else
  exit $?
fi
