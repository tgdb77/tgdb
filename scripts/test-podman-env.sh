#!/usr/bin/env bash

# TGDB 通用 Podman 測試環境啟動器
# 用途：每次開啟一個全新容器，掛載目前 repo，供開發者手動或指定命令測試。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${TGDB_TEST_IMAGE:-docker.io/library/debian:13}"
CONTAINER_NAME_DEFAULT="tgdb-dev-test-$(date +%Y%m%d%H%M%S)-$$"
CONTAINER_NAME="${TGDB_TEST_CONTAINER_NAME:-$CONTAINER_NAME_DEFAULT}"
BOOTSTRAP=0
TEST_CMD=""
NESTED_PODMAN=0

usage() {
  echo "用法: $0 [--image <image>] [--name <container_name>] [--bootstrap] [--nested-podman] [--cmd '<command>']"
  echo ""
  echo "選項："
  echo "  --image      Podman 映像（預設：$IMAGE）"
  echo "  --name       容器名稱（預設：自動產生唯一名稱）"
  echo "  --bootstrap  進入容器前先安裝常見測試工具（apt-get）"
  echo "  --nested-podman  以特權模式啟動容器，供容器內再次執行 Podman"
  echo "  --cmd        容器啟動後直接執行命令（不進入互動 shell）"
  echo "  -h, --help   顯示說明"
  echo ""
  echo "範例："
  echo "  $0"
  echo "  $0 --cmd 'bash ./tgdb.sh 2'"
  echo "  $0 --bootstrap --cmd 'bash scripts/lint.sh'"
  echo "  $0 --nested-podman --cmd 'bash ./tgdb.sh 5 1'"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --image)
      [ "$#" -ge 2 ] || { echo "❌ --image 缺少參數"; exit 2; }
      IMAGE="$2"
      shift 2
      ;;
    --name)
      [ "$#" -ge 2 ] || { echo "❌ --name 缺少參數"; exit 2; }
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --bootstrap)
      BOOTSTRAP=1
      shift
      ;;
    --nested-podman)
      NESTED_PODMAN=1
      shift
      ;;
    --cmd)
      [ "$#" -ge 2 ] || { echo "❌ --cmd 缺少參數"; exit 2; }
      TEST_CMD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "❌ 不支援的參數：$1"
      usage
      exit 2
      ;;
  esac
done

if ! command -v podman >/dev/null 2>&1; then
  echo "❌ 找不到 podman，請先安裝後再執行。"
  exit 1
fi

PODMAN_TTY_ARGS=(-i)
if [ -t 0 ] && [ -t 1 ]; then
  PODMAN_TTY_ARGS=(-it)
fi

if [ -z "$TEST_CMD" ] && { [ ! -t 0 ] || [ ! -t 1 ]; }; then
  echo "❌ 目前非互動終端，請加上 --cmd 指定要執行的命令。"
  exit 2
fi

echo "==> 啟動 TGDB 開發測試容器"
echo "    映像：$IMAGE"
echo "    容器：$CONTAINER_NAME"
echo "    工作目錄：/workspace/tgdb"
if [ "$NESTED_PODMAN" -eq 1 ]; then
  echo "    模式：nested Podman（--privileged）"
fi

PODMAN_EXTRA_ARGS=()
if [ "$NESTED_PODMAN" -eq 1 ]; then
  PODMAN_EXTRA_ARGS+=(--privileged --security-opt label=disable)
fi

exec podman run --rm "${PODMAN_TTY_ARGS[@]}" \
  "${PODMAN_EXTRA_ARGS[@]}" \
  --name "$CONTAINER_NAME" \
  -e TERM="${TERM:-xterm}" \
  -e TGDB_TEST_ENV=1 \
  -e TGDB_TEST_BOOTSTRAP="$BOOTSTRAP" \
  -e TGDB_TEST_CMD="$TEST_CMD" \
  -e TGDB_TEST_NESTED_PODMAN="$NESTED_PODMAN" \
  -v "$ROOT_DIR:/workspace/tgdb:Z" \
  -w /workspace/tgdb \
  "$IMAGE" \
  bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [ "${TGDB_TEST_BOOTSTRAP:-0}" = "1" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "==> 安裝測試工具（bootstrap）"
    apt-get update >/dev/null
    apt-get install -y ca-certificates curl git procps iproute2 util-linux sudo expect shellcheck >/dev/null
  else
    echo "⚠️ 目前映像不支援 apt-get，已略過 bootstrap。"
  fi
fi

if [ -n "${TGDB_TEST_CMD:-}" ]; then
  echo "==> 執行命令：${TGDB_TEST_CMD}"
  exec bash -lc "${TGDB_TEST_CMD}"
fi

echo "==> 已進入測試容器，可開始手動驗證"
echo "    常用指令："
echo "    - bash ./tgdb.sh"
echo "    - bash ./tgdb.sh 2"
exec bash
'
