#!/bin/bash

# TGDB AppSpec（宣告式部署規格）執行器
# 目的：
# - 讓 apps-p.sh 在找不到 app_<service>_<action> 時，可依 app.spec 自動完成部署流程
#
# 注意：
# - 本檔案為 library，會被 source；請勿在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_APPS_APP_SPEC_EXEC_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_APPS_APP_SPEC_EXEC_LOADED=1

APPSPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$APPSPEC_DIR/../core/bootstrap.sh"

# shellcheck source=src/apps/app_spec.sh
source "$APPSPEC_DIR/app_spec.sh"

APPSPEC_EXEC_DIR="$APPSPEC_DIR/app_spec_exec"

# shellcheck source=src/apps/app_spec_exec/base.sh
source "$APPSPEC_EXEC_DIR/base.sh"
# shellcheck source=src/apps/app_spec_exec/input_vars_cli.sh
source "$APPSPEC_EXEC_DIR/input_vars_cli.sh"
# shellcheck source=src/apps/app_spec_exec/deploy.sh
source "$APPSPEC_EXEC_DIR/deploy.sh"
# shellcheck source=src/apps/app_spec_exec/records.sh
source "$APPSPEC_EXEC_DIR/records.sh"
# shellcheck source=src/apps/app_spec_exec/manage.sh
source "$APPSPEC_EXEC_DIR/manage.sh"
# shellcheck source=src/apps/app_spec_exec/dispatch.sh
source "$APPSPEC_EXEC_DIR/dispatch.sh"

