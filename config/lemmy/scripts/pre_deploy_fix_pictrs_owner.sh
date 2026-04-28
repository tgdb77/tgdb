#!/bin/bash

set -euo pipefail

SERVICE="${1:-lemmy}"
NAME="${2:-}"
INSTANCE_DIR="${3:-}"

if [ -z "$INSTANCE_DIR" ] || [ ! -d "$INSTANCE_DIR" ]; then
  echo "❌ 找不到 Lemmy instance_dir，無法調整 pict-rs 目錄權限。($SERVICE/$NAME)" >&2
  exit 1
fi

TARGET_DIR="$INSTANCE_DIR/pictrs"
CONFIG_FILE="$INSTANCE_DIR/lemmy.hjson"
mkdir -p "$TARGET_DIR"

if [ -f "$CONFIG_FILE" ]; then
  echo "ℹ️ 正在調整 Lemmy 設定檔權限：$CONFIG_FILE -> 644"
  chmod 0644 "$CONFIG_FILE"
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "⚠️ 系統未安裝 podman，改用寬鬆權限模式讓 pict-rs 可寫入：$TARGET_DIR" >&2
  chmod -R ugo+rwX "$TARGET_DIR"
  exit 0
fi

echo "ℹ️ 正在調整 pict-rs 目錄權限：$TARGET_DIR -> 991:991（podman userns）"
if podman unshare chown -R 991:991 "$TARGET_DIR"; then
  echo "✅ pict-rs 目錄權限已調整完成。"
  exit 0
fi

echo "⚠️ podman userns chown 失敗，改用寬鬆權限模式讓 pict-rs 可寫入：$TARGET_DIR" >&2
chmod -R ugo+rwX "$TARGET_DIR"
exit 0
