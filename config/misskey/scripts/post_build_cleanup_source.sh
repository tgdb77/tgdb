#!/bin/bash

set -euo pipefail

SERVICE="${1:-misskey}"
NAME="${2:-}"

if [ -z "$NAME" ]; then
  echo "❌ 找不到 Misskey 實例名稱，無法清理 build context。($SERVICE)" >&2
  exit 1
fi

BUILD_DIR="/tmp/tgdb-build-misskey-${NAME}"
case "$BUILD_DIR" in
  /tmp/tgdb-build-misskey-*) ;;
  *)
    echo "❌ build 暫存目錄不合法：$BUILD_DIR" >&2
    exit 1
    ;;
esac

if [ -d "$BUILD_DIR" ]; then
  rm -rf "$BUILD_DIR"
  echo "✅ 已清理 Misskey build context：$BUILD_DIR"
else
  echo "ℹ️ Misskey build context 已不存在，略過清理：$BUILD_DIR"
fi
