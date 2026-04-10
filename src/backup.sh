#!/bin/bash

# 全系統備份管理模組
# 說明：本模組已依功能拆分至 src/backup/。
# shellcheck disable=SC2119 # ui_pause 使用預設訊息即可，無需轉傳參數
# 注意：此檔案可能會被 tgdb.sh source，也可能被 systemd timer 直接執行。
# 為避免污染呼叫端 shell options，僅在「直接執行」時啟用嚴格模式。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

if [[ "${BASH_SOURCE[0]}" != "$0" ]] && [ -n "${_TGDB_BACKUP_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_MODULE_SRC_DIR="$SCRIPT_DIR/backup"

# 載入共用工具
# shellcheck source=src/core/bootstrap.sh
source "$SCRIPT_DIR/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SCRIPT_DIR/core/quadlet_common.sh"

# 確保已載入系統設定（TGDB_DIR 等），避免在 systemd/獨立執行時變數未定義。
load_system_config

BACKUP_PREFIX="tgdb-backup"
BACKUP_MAX_COUNT=3
BACKUP_SELECT_PREFIX="tgdb-backup-select"
BACKUP_SELECT_MAX_COUNT=10
BACKUP_ROOT="${TGDB_BACKUP_ROOT:-$(dirname "$TGDB_DIR")}"
BACKUP_DIR="$BACKUP_ROOT/backup"

BACKUP_CONFIG_DIR="$(rm_persist_config_dir)"
CONTAINERS_SYSTEMD_DIR="$(rm_user_units_dir)"
BACKUP_QUADLET_RUNTIME_ARCHIVE_DIRNAME="quadlet-runtime"
BACKUP_QUADLET_RUNTIME_DIR="$BACKUP_ROOT/$BACKUP_QUADLET_RUNTIME_ARCHIVE_DIRNAME"
BACKUP_TIMER_UNITS_DIR="$(rm_persist_timer_dir)"

USER_SD_DIR="$(rm_user_systemd_dir)"
# shellcheck disable=SC2034 # 供 backup_timers.sh / 子模組讀取
BACKUP_SERVICE_NAME="tgdb-backup.service"
# shellcheck disable=SC2034 # 供 backup_timers.sh / 子模組讀取
BACKUP_TIMER_NAME="tgdb-backup.timer"
# shellcheck disable=SC2034 # 供 backup_timers.sh / 子模組讀取
BACKUP_SELECT_SERVICE_NAME="tgdb-backup-select.service"
# shellcheck disable=SC2034 # 供 backup_timers.sh / 子模組讀取
BACKUP_SELECT_TIMER_NAME="tgdb-backup-select.timer"

# 避免在 set -u 模式下引用未初始化陣列
BACKUP_ACTIVE_CONTAINERS=()
BACKUP_ACTIVE_PODS=()
BACKUP_SELECTED_INSTANCES=()

# 備份模組設定（放在持久化 config 內，會一起被備份/還原）
BACKUP_MODULE_DIR="$BACKUP_CONFIG_DIR/backup"
BACKUP_MODULE_CONFIG_FILE="$BACKUP_MODULE_DIR/config.conf"

# shellcheck source=src/backup/backup_config.sh
source "$BACKUP_MODULE_SRC_DIR/backup_config.sh"
# shellcheck source=src/backup/backup_units.sh
source "$BACKUP_MODULE_SRC_DIR/backup_units.sh"
# shellcheck source=src/backup/backup_archives.sh
source "$BACKUP_MODULE_SRC_DIR/backup_archives.sh"
# shellcheck source=src/backup/backup_instances.sh
source "$BACKUP_MODULE_SRC_DIR/backup_instances.sh"
# shellcheck source=src/backup/backup_ops.sh
source "$BACKUP_MODULE_SRC_DIR/backup_ops.sh"
# shellcheck source=src/backup/backup_manage.sh
source "$BACKUP_MODULE_SRC_DIR/backup_manage.sh"
# shellcheck source=src/backup/backup_timers.sh
source "$BACKUP_MODULE_SRC_DIR/backup_timers.sh"
# shellcheck source=src/backup/backup_menu.sh
source "$BACKUP_MODULE_SRC_DIR/backup_menu.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  backup_cli_main "$@" || exit $?
fi
