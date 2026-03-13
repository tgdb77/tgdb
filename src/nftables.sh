#!/bin/bash

# TGDB nftables 管理模組（聚合器）
# 說明：原本的單一大檔已依功能拆分至 src/nftables/，
# 此檔案保留為對外入口以維持相容性。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$SCRIPT_DIR/core/bootstrap.sh"

# shellcheck disable=SC2034 # 供子模組共用的全域狀態變數
NFTABLES_BACKUP_DIR=""
NFTABLES_MODULE_DIR="$SCRIPT_DIR/nftables"

_nftables_source_or_die() {
    local file="$1"
    if [ -f "$file" ]; then
        # shellcheck disable=SC1090 # 子模組於執行期載入
        source "$file"
        return 0
    fi
    tgdb_fail "找不到 nftables 子模組：$file" 1 || true
    return 1
}

_nftables_source_or_die "$NFTABLES_MODULE_DIR/common.sh" || return 1
_nftables_source_or_die "$NFTABLES_MODULE_DIR/setup.sh" || return 1
_nftables_source_or_die "$NFTABLES_MODULE_DIR/tailnet_forward.sh" || return 1
_nftables_source_or_die "$NFTABLES_MODULE_DIR/port_management.sh" || return 1
_nftables_source_or_die "$NFTABLES_MODULE_DIR/ip_ping.sh" || return 1
_nftables_source_or_die "$NFTABLES_MODULE_DIR/backup_restore.sh" || return 1
_nftables_source_or_die "$NFTABLES_MODULE_DIR/menu.sh" || return 1
