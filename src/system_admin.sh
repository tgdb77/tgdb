#!/bin/bash

# 系統管理功能模組（聚合器）
# 說明：將較易「高度訂製」的功能拆到 src/system/ 下，方便依需求調整而不影響主入口。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

# 確保 SRC_DIR 存在（一般由 tgdb.sh 設定），避免直接 source 時找不到路徑
if [ -z "${SRC_DIR:-}" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# 確保共用工具已載入（避免被單獨 source 時缺少 tgdb_* 函式）
# shellcheck source=src/core/bootstrap.sh
source "$SRC_DIR/core/bootstrap.sh"

SYSTEM_DIR="$SRC_DIR/system"

_system_admin_source_or_die() {
  local file="$1"
  if [ -f "$file" ]; then
    # shellcheck disable=SC1090 # 子模組於執行期載入
    source "$file"
    return 0
  fi
  tgdb_fail "找不到系統子模組：$file" 1 || true
  return 1
}

_system_admin_source_or_die "$SYSTEM_DIR/common.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/users.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/virtual_memory.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/ssh.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/dns.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/cron.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/kernel.sh" || return 1

_system_admin_source_or_die "$SYSTEM_DIR/hostname.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/timezone.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/ports.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/cli-s.sh" || return 1
_system_admin_source_or_die "$SYSTEM_DIR/menu.sh" || return 1
