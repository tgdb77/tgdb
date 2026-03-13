#!/usr/bin/env bash

# TGDB 專案 lint（預設僅檢查 Git 變更檔）
# - 預設：staged + unstaged + untracked
# - --cached：僅 staged
# - --unstaged：僅 unstaged + untracked
# - --files：直接指定要檢查的檔案（供 CI 或手動指定）
# 檢查內容：
# - bash -n：語法檢查（不執行腳本）
# - shellcheck：靜態分析（不執行腳本）
#   - 快速模式：不追蹤 source，適合日常開發
#   - 完整模式：內嵌 source-path 設定並追蹤 source，但只檢查受影響模組入口

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="all"
SHELLCHECK_MODE="${TGDB_LINT_MODE:-fast}"
USE_EXPLICIT_FILES=0
EXPLICIT_FILES=()

usage() {
  echo "用法: $0 [--all|--cached|--unstaged] [--fast|--deep]"
  echo "      $0 [--fast|--deep] --files [<path> ...]"
  echo "  --all       檢查 staged + unstaged + untracked（預設）"
  echo "  --cached    僅檢查 staged"
  echo "  --unstaged  僅檢查 unstaged + untracked"
  echo "  --files     直接指定要檢查的檔案"
  echo "  --fast      快速模式（預設）：不追蹤 source，速度較快"
  echo "  --deep      完整模式：追蹤 source，但僅檢查受影響模組入口"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      MODE="all"
      ;;
    --cached)
      MODE="cached"
      ;;
    --unstaged)
      MODE="unstaged"
      ;;
    --fast)
      SHELLCHECK_MODE="fast"
      ;;
    --deep)
      SHELLCHECK_MODE="deep"
      ;;
    --files)
      USE_EXPLICIT_FILES=1
      shift
      EXPLICIT_FILES=("$@")
      break
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
  shift
done

case "$SHELLCHECK_MODE" in
  fast|deep)
    ;;
  *)
    echo "❌ 不支援的 TGDB_LINT_MODE：$SHELLCHECK_MODE"
    echo "   可用值：fast / deep"
    exit 2
    ;;
esac

if ! command -v git >/dev/null 2>&1; then
  if [ "$USE_EXPLICIT_FILES" != "1" ]; then
    echo "❌ 找不到 git，無法檢查變更檔。"
    exit 1
  fi
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "❌ 找不到 shellcheck，請先安裝後再執行 lint。"
  echo "   Debian/Ubuntu: sudo apt-get install -y shellcheck"
  echo "   Fedora/RHEL:   sudo dnf install -y ShellCheck"
  echo "   Arch:          sudo pacman -S --noconfirm shellcheck"
  exit 1
fi

cd "$ROOT_DIR"

collect_changed_candidates() {
  case "$MODE" in
    cached)
      git diff --name-only --cached --diff-filter=ACMR || true
      ;;
    unstaged)
      git diff --name-only --diff-filter=ACMR || true
      git ls-files --others --exclude-standard || true
      ;;
    all)
      git diff --name-only --diff-filter=ACMR || true
      git diff --name-only --cached --diff-filter=ACMR || true
      git ls-files --others --exclude-standard || true
      ;;
  esac
}

is_lint_target() {
  local rel="$1"
  [ -n "${rel:-}" ] || return 1
  [ "$rel" = "tgdb.sh" ] && return 0
  [[ "$rel" == *.sh ]] || return 1
  [ "$rel" = "plan/kejilion.sh" ] && return 1
  return 0
}

normalize_explicit_candidates() {
  local input rel
  for input in "${EXPLICIT_FILES[@]}"; do
    [ -n "${input:-}" ] || continue
    case "$input" in
      "$ROOT_DIR"/*)
        rel="${input#"$ROOT_DIR"/}"
        ;;
      /*)
        continue
        ;;
      *)
        rel="${input#./}"
        ;;
    esac
    is_lint_target "$rel" || continue
    [ -f "$ROOT_DIR/$rel" ] || continue
    printf '%s\n' "$ROOT_DIR/$rel"
  done
}

add_unique_target() {
  local rel="$1"
  local target_array_name="$2"
  local -n target_array_ref="$target_array_name"
  local abs="$ROOT_DIR/$rel"
  local existing

  [ -f "$abs" ] || return 0
  for existing in "${target_array_ref[@]}"; do
    [ "$existing" = "$abs" ] && return 0
  done
  target_array_ref+=("$abs")
}

append_deep_module_targets() {
  local rel="$1"
  local target_array_name="$2"

  # 模組對應表：子模組 / 子目錄變更時，收斂到對外入口做深度檢查。
  case "$rel" in
    tgdb.sh)
      add_unique_target "tgdb.sh" "$target_array_name"
      add_unique_target "src/core/bootstrap.sh" "$target_array_name"
      add_unique_target "src/core/routes.sh" "$target_array_name"
      add_unique_target "src/core/cli.sh" "$target_array_name"
      add_unique_target "src/system.sh" "$target_array_name"
      ;;
    src/apps-p.sh|src/apps/*)
      add_unique_target "src/apps-p.sh" "$target_array_name"
      ;;
    src/podman.sh|src/podman/*)
      add_unique_target "src/podman.sh" "$target_array_name"
      ;;
    src/system_admin.sh|src/system/*)
      add_unique_target "src/system_admin.sh" "$target_array_name"
      ;;
    src/system.sh)
      add_unique_target "src/system.sh" "$target_array_name"
      ;;
    src/nftables.sh|src/nftables/*)
      add_unique_target "src/nftables.sh" "$target_array_name"
      ;;
    src/timer.sh|src/timer/*)
      add_unique_target "src/timer.sh" "$target_array_name"
      ;;
    src/advanced/dbadmin-p.sh|src/advanced/dbadmin/*)
      add_unique_target "src/advanced/dbadmin-p.sh" "$target_array_name"
      ;;
    src/advanced/kopia-p.sh|src/advanced/kopia/*)
      add_unique_target "src/advanced/kopia-p.sh" "$target_array_name"
      ;;
    src/advanced/nginx-p.sh|src/advanced/nginx/*)
      add_unique_target "src/advanced/nginx-p.sh" "$target_array_name"
      ;;
    src/advanced/gameserver-p.sh|src/advanced/gameserver/*)
      add_unique_target "src/advanced/gameserver-p.sh" "$target_array_name"
      ;;
    src/advanced/*.sh)
      add_unique_target "$rel" "$target_array_name"
      ;;
    *)
      add_unique_target "$rel" "$target_array_name"
      ;;
  esac
}

collect_shellcheck_targets() {
  local mode="$1"
  shift
  local input rel
  local -a targets=()

  if [ "$mode" = "deep" ]; then
    for input in "$@"; do
      rel="${input#"$ROOT_DIR"/}"
      append_deep_module_targets "$rel" targets
    done
  else
    for input in "$@"; do
      rel="${input#"$ROOT_DIR"/}"
      add_unique_target "$rel" targets
    done
  fi

  if [ "${#targets[@]}" -eq 0 ]; then
    printf '%s\n' "$@"
    return 0
  fi

  printf '%s\n' "${targets[@]}"
}

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

if [ "$USE_EXPLICIT_FILES" != "1" ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "❌ 目前路徑不是 Git 倉庫：$ROOT_DIR"
    exit 1
  fi
fi

mapfile -t files < <(
  if [ "$USE_EXPLICIT_FILES" = "1" ]; then
    normalize_explicit_candidates
  else
    collect_changed_candidates \
      | awk 'NF' \
      | LC_ALL=C sort -u \
      | while IFS= read -r rel; do
          [ -n "${rel:-}" ] || continue
          is_lint_target "$rel" || continue
          [ -f "$ROOT_DIR/$rel" ] || continue
          printf '%s\n' "$ROOT_DIR/$rel"
        done
  fi \
    | LC_ALL=C sort -u
)

if [ "${#files[@]}" -eq 0 ]; then
  if [ "$USE_EXPLICIT_FILES" = "1" ]; then
    echo "ℹ️ 沒有可檢查的 Shell 檔案（來源：--files）。"
  else
    echo "ℹ️ 沒有可檢查的 Shell 變更檔（mode=$MODE）。"
  fi
  exit 0
fi

mapfile -t shellcheck_targets < <(
  collect_shellcheck_targets "$SHELLCHECK_MODE" "${files[@]}" | LC_ALL=C sort -u
)

shellcheck_mode_label=""
shellcheck_batch_size=1
shellcheck_jobs=1
shellcheck_args=()
shellcheck_severity="${TGDB_LINT_SEVERITY:-warning}"
shellcheck_excludes="SC1090,SC1091,SC2317"
shellcheck_source_paths=(src src/core src/apps .)

case "$SHELLCHECK_MODE" in
  fast)
    shellcheck_mode_label="快速模式（不追蹤 source）"
    shellcheck_batch_size="${TGDB_LINT_BATCH_SIZE:-12}"
    shellcheck_jobs="$(detect_shellcheck_jobs)"
    shellcheck_args=(--norc -s bash -e "$shellcheck_excludes" -S "$shellcheck_severity")
    ;;
  deep)
    shellcheck_mode_label="完整模式（追蹤 source，僅受影響模組入口）"
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

if [ "$USE_EXPLICIT_FILES" = "1" ]; then
  echo "==> lint 目標（來源=--files）：${#files[@]} 個檔案"
else
  echo "==> lint 目標（mode=$MODE）：${#files[@]} 個檔案"
fi
for f in "${files[@]}"; do
  printf ' - %s\n' "${f#"$ROOT_DIR"/}"
done

echo "==> bash -n（語法檢查）"
for f in "${files[@]}"; do
  bash -n "$f"
done

if [ "${TGDB_LINT_EXTENDED:-0}" != "1" ]; then
  shellcheck_args+=(--extended-analysis=false)
fi

echo "==> shellcheck（靜態分析，$shellcheck_mode_label）"
echo "    目標數：${#shellcheck_targets[@]}，批次大小：$shellcheck_batch_size，併行數：$shellcheck_jobs"
if [ "$SHELLCHECK_MODE" = "deep" ]; then
  for f in "${shellcheck_targets[@]}"; do
    printf '    - %s\n' "${f#"$ROOT_DIR"/}"
  done
fi
printf '%s\0' "${shellcheck_targets[@]}" \
  | xargs -0 -r -n "$shellcheck_batch_size" -P "$shellcheck_jobs" shellcheck "${shellcheck_args[@]}"

echo "✅ 變更檔 lint 通過"
