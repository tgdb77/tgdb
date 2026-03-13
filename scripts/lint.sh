#!/usr/bin/env bash

# TGDB 專案 lint（預設為快速模式）
# - bash -n：語法檢查（不執行腳本）
# - shellcheck：靜態分析（不執行腳本）
#   - 快速模式：不追蹤 source，適合日常開發
#   - 完整模式：內嵌 source-path 設定並追蹤 source，較慢，建議按需執行 --deep

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${TGDB_LINT_MODE:-fast}"

usage() {
  echo "用法: $0 [--fast|--deep]"
  echo "  --fast  快速模式（預設）：不追蹤 source，速度較快"
  echo "  --deep  完整模式：追蹤 source，耗時較久"
}

if [ "$#" -gt 1 ]; then
  usage
  exit 2
fi

if [ "$#" -eq 1 ]; then
  case "$1" in
    --fast)
      MODE="fast"
      ;;
    --deep)
      MODE="deep"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
fi

case "$MODE" in
  fast|deep)
    ;;
  *)
    echo "❌ 不支援的 TGDB_LINT_MODE：$MODE"
    echo "   可用值：fast / deep"
    exit 2
    ;;
esac

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "❌ 找不到 shellcheck，請先安裝後再執行 lint。"
  echo "   Debian/Ubuntu: sudo apt-get install -y shellcheck"
  echo "   Fedora/RHEL:   sudo dnf install -y ShellCheck"
  echo "   Arch:          sudo pacman -S --noconfirm shellcheck"
  exit 1
fi

mapfile -t files < <(
  find "$ROOT_DIR" \
    -type f \( -name "*.sh" -o -name "tgdb.sh" \) \
    -not -path "*/.git/*" \
    -not -path "*/plan/kejilion.sh" \
    -print \
  | LC_ALL=C sort
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "❌ 找不到任何 .sh 檔案"
  exit 1
fi

detect_shellcheck_jobs() {
  local jobs="${TGDB_LINT_JOBS:-}"
  if [ -z "$jobs" ]; then
    if command -v getconf >/dev/null 2>&1; then
      jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    elif command -v nproc >/dev/null 2>&1; then
      jobs="$(nproc 2>/dev/null || true)"
    else
      jobs=1
    fi
  fi

  if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    jobs=1
  fi
  if [ "$jobs" -gt 4 ]; then
    jobs=4
  fi
  printf '%s\n' "$jobs"
}

shellcheck_mode_label=""
shellcheck_batch_size=1
shellcheck_jobs=1
shellcheck_args=()
shellcheck_severity="${TGDB_LINT_SEVERITY:-warning}"
shellcheck_excludes="SC1090,SC1091,SC2317"
shellcheck_source_paths=(src src/core src/apps .)

case "$MODE" in
  fast)
    shellcheck_mode_label="快速模式（不追蹤 source）"
    shellcheck_batch_size="${TGDB_LINT_BATCH_SIZE:-12}"
    shellcheck_jobs="$(detect_shellcheck_jobs)"
    shellcheck_args=(--norc -s bash -e "$shellcheck_excludes" -S "$shellcheck_severity")
    ;;
  deep)
    shellcheck_mode_label="完整模式（追蹤 source）"
    shellcheck_batch_size="${TGDB_LINT_BATCH_SIZE:-1}"
    shellcheck_jobs="${TGDB_LINT_JOBS:-1}"
    shellcheck_args=(--norc -s bash -x -e "$shellcheck_excludes" -S "$shellcheck_severity")
    for path in "${shellcheck_source_paths[@]}"; do
      shellcheck_args+=(-P "$path")
    done
    ;;
esac

if [[ ! "$shellcheck_batch_size" =~ ^[1-9][0-9]*$ ]]; then
  shellcheck_batch_size=1
fi
if [[ ! "$shellcheck_jobs" =~ ^[1-9][0-9]*$ ]]; then
  shellcheck_jobs=1
fi

echo "==> bash -n（語法檢查）"
for f in "${files[@]}"; do
  bash -n "$f"
done

if [ "${TGDB_LINT_EXTENDED:-0}" != "1" ]; then
  shellcheck_args+=(--extended-analysis=false)
fi

echo "==> shellcheck（靜態分析，$shellcheck_mode_label）"
echo "    檔案數：${#files[@]}，批次大小：$shellcheck_batch_size，併行數：$shellcheck_jobs"
printf '%s\0' "${files[@]}" \
  | xargs -0 -r -n "$shellcheck_batch_size" -P "$shellcheck_jobs" shellcheck "${shellcheck_args[@]}"

echo "✅ lint 通過"
