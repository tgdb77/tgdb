#!/bin/bash

# Podman/Quadlet 管理模組（聚合器）
# 說明：原本的單一大檔已依功能拆分至 src/podman/，此檔案保留為對外入口以維持相容性。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 確保 SRC_DIR 存在（一般由 tgdb.sh 設定），避免直接 source 時找不到路徑
if [ -z "${SRC_DIR:-}" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# 確保共用工具已載入（避免被單獨 source 時缺少 tgdb_* / rm_* 等函式）
# shellcheck source=src/core/bootstrap.sh
source "$SRC_DIR/core/bootstrap.sh"

# Quadlet 共用（_systemctl_user_try 等）
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_DIR/core/quadlet_common.sh"

PODMAN_DIR="$SRC_DIR/podman"

_podman_source_or_die() {
  local file="$1"
  if [ -f "$file" ]; then
    # shellcheck disable=SC1090 # 子模組於執行期載入
    source "$file"
    return 0
  fi
  tgdb_fail "找不到 Podman 子模組：$file" 1 || true
  return 1
}

_podman_source_or_die "$PODMAN_DIR/common.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/containers_config.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/install.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/quadlet_units.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/quadlet_pod.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/quadlet_actions.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/quadlet_files.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/auto_update.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/uninstall.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/cli.sh" || return 1
_podman_source_or_die "$PODMAN_DIR/menu.sh" || return 1
