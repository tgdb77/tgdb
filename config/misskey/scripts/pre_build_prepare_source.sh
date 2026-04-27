#!/bin/bash

set -euo pipefail

SERVICE="${1:-misskey}"
NAME="${2:-}"

if [ -z "$NAME" ]; then
  echo "❌ 找不到 Misskey 實例名稱，無法準備 build context。($SERVICE)" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "❌ 系統未安裝 git，無法抓取 Misskey 原始碼。($SERVICE/$NAME)" >&2
  exit 1
fi

BUILD_REPO="${MISSKEY_GIT_REPO:-https://github.com/misskey-dev/misskey.git}"
BUILD_REF="${MISSKEY_GIT_REF:-master}"
BUILD_DIR="/tmp/tgdb-build-misskey-${NAME}"

case "$BUILD_DIR" in
  /tmp/tgdb-build-misskey-*) ;;
  *)
    echo "❌ build 暫存目錄不合法：$BUILD_DIR" >&2
    exit 1
    ;;
esac

echo "ℹ️ 正在準備 Misskey build context..."
echo "   - Repo：$BUILD_REPO"
echo "   - Ref：$BUILD_REF"
echo "   - 目錄：$BUILD_DIR"

rm -rf "$BUILD_DIR"

git clone --recursive --branch "$BUILD_REF" "$BUILD_REPO" "$BUILD_DIR"

if [ ! -f "$BUILD_DIR/Dockerfile" ]; then
  echo "❌ Misskey 原始碼中找不到 Dockerfile：$BUILD_DIR/Dockerfile" >&2
  exit 1
fi

# Podman 在未設定 unqualified-search-registries 時，無法解析 Dockerfile 內的短名映像。
# Misskey upstream 目前使用 node:... 作為 base image，這裡改寫為完整名稱，避免依賴使用者環境。
if ! sed -E -i \
  's#^(FROM([[:space:]]+--platform=[^[:space:]]+)?[[:space:]]+)node:#\1docker.io/library/node:#' \
  "$BUILD_DIR/Dockerfile"; then
  echo "❌ 無法改寫 Misskey Dockerfile 的 base image：$BUILD_DIR/Dockerfile" >&2
  exit 1
fi

# 部分 Podman/Buildah 版本尚未支援 Dockerfile 的 COPY --link。
# 這裡退回一般 COPY 以提高相容性。
if ! sed -E -i 's#^([[:space:]]*COPY)[[:space:]]+--link([[:space:]]+)#\1\2#' "$BUILD_DIR/Dockerfile"; then
  echo "❌ 無法改寫 Misskey Dockerfile 的 COPY --link：$BUILD_DIR/Dockerfile" >&2
  exit 1
fi

echo "✅ Misskey build context 已準備完成。"
