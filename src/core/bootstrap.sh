#!/bin/bash

# TGDB 核心載入入口（Bootstrap）
# 目的：
# - 統一推導 repo/src 路徑，避免各模組重複寫 SCRIPT_DIR/SRC_ROOT 邏輯
# - 統一載入 core/utils.sh（由其再載入 ui/record_manager 等共用模組）
# 注意：此檔案為 library，會被 source，請勿在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；但若需要「更新後重新載入」，可暫時設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_CORE_BOOTSTRAP_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_BOOTSTRAP_LOADED=1

_tgdb_bootstrap_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

_TGDB_BOOTSTRAP_DIR="$(_tgdb_bootstrap_dir)"

# 由 bootstrap 位置推導：src/core -> src -> repo
SRC_DIR="${SRC_DIR:-$(cd "$_TGDB_BOOTSTRAP_DIR/.." && pwd)}"
TGDB_REPO_DIR="${TGDB_REPO_DIR:-$(cd "$SRC_DIR/.." && pwd)}"

# 向後相容別名（部分模組使用 SRC_ROOT / TGDB_ROOT_DIR）
SRC_ROOT="${SRC_ROOT:-$SRC_DIR}"
TGDB_ROOT_DIR="${TGDB_ROOT_DIR:-$TGDB_REPO_DIR}"

# shellcheck source=src/core/utils.sh
source "$SRC_DIR/core/utils.sh"

# 入口依賴檢查工具（可選載入；缺檔不阻擋啟動）
# shellcheck source=src/core/dependencies.sh
[ -f "$SRC_DIR/core/dependencies.sh" ] && source "$SRC_DIR/core/dependencies.sh"
