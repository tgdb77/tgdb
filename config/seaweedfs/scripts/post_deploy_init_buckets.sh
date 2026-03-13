#!/usr/bin/env bash

# SeaweedFS 部署後初始化：建立 /buckets 與預設 bucket 目錄
#
# 說明：
# - 本腳本由 AppSpec `post_deploy=` 呼叫（enable/start 後執行）
# - 需可重複執行（idempotent），因此建立已存在的目錄不視為失敗
# - 初始化失敗不應影響服務啟動（交由 app.spec 的 allow_fail 控制）

set -euo pipefail

service="${1:-seaweedfs}"
name="${2:-}"
instance_dir_arg="${3:-}"
host_port_arg="${4:-}"

# 優先使用引擎注入的變數；其次使用參數；最後再用 TGDB_DIR/name 推導
INSTANCE_DIR="${instance_dir:-${instance_dir_arg:-}}"
if [ -z "$INSTANCE_DIR" ] && [ -n "${TGDB_DIR:-}" ] && [ -n "$name" ]; then
  INSTANCE_DIR="$TGDB_DIR/$name"
fi

_env_value() {
  local env_file="$1" key="$2"
  [ -f "$env_file" ] || return 1
  awk -F= -v k="$key" '
    $1==k {
      $1=""
      sub(/^=/, "", $0)
      print $0
      exit
    }
  ' "$env_file" 2>/dev/null
}

env_file=""
if [ -n "$INSTANCE_DIR" ]; then
  env_file="$INSTANCE_DIR/.env"
fi

FILER_PORT="${SEAWEEDFS_FILER_PORT:-${host_port:-${host_port_arg:-}}}"
if [ -z "$FILER_PORT" ] && [ -f "$env_file" ]; then
  FILER_PORT="$(_env_value "$env_file" "SEAWEEDFS_FILER_PORT" 2>/dev/null || true)"
fi
if [ -z "$FILER_PORT" ]; then
  # SeaweedFS filer 預設對外入口（TGDB seaweedfs base_port）
  FILER_PORT="8989"
fi

BUCKET_NAME="${SEAWEEDFS_BUCKET_NAME:-${bucket_name:-}}"
if [ -z "$BUCKET_NAME" ] && [ -f "$env_file" ]; then
  BUCKET_NAME="$(_env_value "$env_file" "SEAWEEDFS_BUCKET_NAME" 2>/dev/null || true)"
fi
if [ -z "$BUCKET_NAME" ]; then
  BUCKET_NAME="seaweedfs"
fi

case "$BUCKET_NAME" in
  *"/"*|*"\\"*|*" "*|*$'\t'*|*$'\r'*|*$'\n'*)
    echo "⚠️ 儲存桶名稱無效，已跳過初始化：$BUCKET_NAME" >&2
    exit 0
    ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "⚠️ 找不到 curl，無法自動建立 SeaweedFS buckets 目錄（/buckets）。($service/$name)" >&2
  exit 0
fi

base_url="http://127.0.0.1:${FILER_PORT}"

timeout="${SEAWEEDFS_POST_DEPLOY_TIMEOUT:-60}"
if [[ ! "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -le 0 ] 2>/dev/null; then
  timeout=60
fi

waited=0
while [ "$waited" -lt "$timeout" ] 2>/dev/null; do
  if curl -sS -o /dev/null --max-time 2 "${base_url}/" 2>/dev/null; then
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

if [ "$waited" -ge "$timeout" ]; then
  echo "⚠️ 等待 SeaweedFS filer 就緒逾時（$base_url），已跳過建立 buckets 目錄。($service/$name)" >&2
  exit 0
fi

_filer_mkdir() {
  local path="$1"
  local p="${path%/}"
  [ -n "$p" ] || return 1

  local url="${base_url}${p}/"
  local code

  code="$(curl -sS -o /dev/null -w "%{http_code}" -X PUT --max-time 5 "$url" 2>/dev/null || echo "000")"
  case "$code" in
    2*|409) return 0 ;;
  esac

  # 相容不同版本/行為：嘗試常見的 mkdir 操作參數
  code="$(curl -sS -o /dev/null -w "%{http_code}" -X POST --max-time 5 "${url}?op=mkdir" 2>/dev/null || echo "000")"
  case "$code" in
    2*|409) return 0 ;;
  esac
  code="$(curl -sS -o /dev/null -w "%{http_code}" -X POST --max-time 5 "${url}?mkdir=true" 2>/dev/null || echo "000")"
  case "$code" in
    2*|409) return 0 ;;
  esac

  return 1
}

# SeaweedFS S3 Gateway 使用 /buckets 作為 buckets root。
_filer_mkdir "/buckets" || true
if ! _filer_mkdir "/buckets/$BUCKET_NAME"; then
  echo "⚠️ 建立 /buckets/$BUCKET_NAME 失敗（請確認 filer API 可用）。($service/$name)" >&2
  exit 0
fi

exit 0
