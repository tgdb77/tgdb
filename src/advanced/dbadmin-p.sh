#!/bin/bash

# 數據庫管理（Web 管理工具：pgAdmin / RedisInsight）入口
# 說明：本模組已依功能拆分至 src/advanced/dbadmin/。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_DBADMIN_P_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_P_LOADED=1

DBADMIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DBADMIN_MODULE_DIR="$DBADMIN_DIR/dbadmin"
SRC_ROOT="$(cd "$DBADMIN_DIR/.." && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"

# 需要復用 apps-p 的 Quadlet 部署/移除核心
# shellcheck source=src/apps-p.sh
source "$SRC_ROOT/apps-p.sh"

# shellcheck source=src/advanced/dbadmin/dbbackup_common.sh
source "$DBADMIN_MODULE_DIR/dbbackup_common.sh"
# shellcheck source=src/advanced/dbadmin/dbbackup_postgres.sh
source "$DBADMIN_MODULE_DIR/dbbackup_postgres.sh"
# shellcheck source=src/advanced/dbadmin/dbbackup_mysql.sh
source "$DBADMIN_MODULE_DIR/dbbackup_mysql.sh"
# shellcheck source=src/advanced/dbadmin/dbbackup_mongo.sh
source "$DBADMIN_MODULE_DIR/dbbackup_mongo.sh"
# shellcheck source=src/advanced/dbadmin/dbbackup_redis.sh
source "$DBADMIN_MODULE_DIR/dbbackup_redis.sh"
# shellcheck source=src/advanced/dbadmin/dbbackup_batch.sh
source "$DBADMIN_MODULE_DIR/dbbackup_batch.sh"
# shellcheck source=src/advanced/dbadmin/dbbackup_menu.sh
source "$DBADMIN_MODULE_DIR/dbbackup_menu.sh"
# shellcheck source=src/advanced/dbadmin/dbbackup_all_cli.sh
source "$DBADMIN_MODULE_DIR/dbbackup_all_cli.sh"

# shellcheck source=src/advanced/dbadmin/dbadmin_common.sh
source "$DBADMIN_MODULE_DIR/dbadmin_common.sh"
# shellcheck source=src/advanced/dbadmin/dbadmin_deploy.sh
source "$DBADMIN_MODULE_DIR/dbadmin_deploy.sh"
# shellcheck source=src/advanced/dbadmin/dbadmin_remove.sh
source "$DBADMIN_MODULE_DIR/dbadmin_remove.sh"
# shellcheck source=src/advanced/dbadmin/dbadmin_timers.sh
source "$DBADMIN_MODULE_DIR/dbadmin_timers.sh"
# shellcheck source=src/advanced/dbadmin/dbadmin_menu.sh
source "$DBADMIN_MODULE_DIR/dbadmin_menu.sh"
