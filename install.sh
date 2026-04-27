#!/usr/bin/env bash

set -euo pipefail

REPO_URL="${TGDB_REPO_URL:-https://github.com/tgdb77/tgdb.git}"
TGDB_PARENT_DIR="$(pwd)"
TGDB_DIR="$TGDB_PARENT_DIR/tgdb"
TGDB_BRANCH="${TGDB_BRANCH:-main}"
TGDB_ARGS=("$@")

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

ensure_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=""
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO_CMD="sudo"
    return 0
  fi

  log_error "此腳本需要 sudo 權限來安裝 git，請先安裝 sudo 或改用 root 執行。"
  exit 1
}

install_git() {
  if command -v git >/dev/null 2>&1; then
    log_info "已偵測到 git，略過安裝。"
    return 0
  fi

  log_info "未偵測到 git，開始安裝..."

  if command -v apt-get >/dev/null 2>&1; then
    $SUDO_CMD apt-get update
    $SUDO_CMD apt-get install -y git
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    $SUDO_CMD dnf install -y git
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    $SUDO_CMD yum install -y git
    return 0
  fi

  if command -v zypper >/dev/null 2>&1; then
    $SUDO_CMD zypper --non-interactive install git
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    $SUDO_CMD pacman -Sy --noconfirm git
    return 0
  fi

  if command -v apk >/dev/null 2>&1; then
    $SUDO_CMD apk add --no-cache git
    return 0
  fi

  log_error "找不到支援的套件管理器，請先手動安裝 git 後重試。"
  exit 1
}

sync_project() {
  if [ -d "$TGDB_DIR/.git" ]; then
    log_info "偵測到既有 TGDB 專案，開始同步..."

    if ! git -C "$TGDB_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      log_error "目錄存在但不是有效的 Git 倉庫：$TGDB_DIR"
      exit 1
    fi

    local origin_url
    origin_url="$(git -C "$TGDB_DIR" remote get-url origin 2>/dev/null || true)"
    if [ -z "$origin_url" ]; then
      log_warn "未偵測到 origin，將自動設定為：$REPO_URL"
      git -C "$TGDB_DIR" remote add origin "$REPO_URL"
      origin_url="$REPO_URL"
    fi

    if [ -n "$origin_url" ] && [ "$origin_url" != "$REPO_URL" ]; then
      log_warn "偵測到不同的 origin：$origin_url"
      log_warn "將自動改為：$REPO_URL"
      git -C "$TGDB_DIR" remote set-url origin "$REPO_URL"
    fi

    git -C "$TGDB_DIR" fetch origin "$TGDB_BRANCH" --depth=1

    if git -C "$TGDB_DIR" show-ref --verify --quiet "refs/heads/$TGDB_BRANCH"; then
      git -C "$TGDB_DIR" checkout "$TGDB_BRANCH"
    else
      git -C "$TGDB_DIR" checkout -b "$TGDB_BRANCH" "origin/$TGDB_BRANCH"
    fi

    if git -C "$TGDB_DIR" diff --quiet && git -C "$TGDB_DIR" diff --cached --quiet; then
      git -C "$TGDB_DIR" pull --ff-only origin "$TGDB_BRANCH"
    else
      log_warn "偵測到未提交變更，為避免覆蓋，已略過 pull。"
    fi

    return 0
  fi

  if [ -e "$TGDB_DIR" ]; then
    log_error "偵測到既有路徑但不是 TGDB Git 倉庫：$TGDB_DIR"
    log_error "請先清理或改名該目錄後再重試。"
    exit 1
  fi

  log_info "將在目前目錄建立 tgdb 並下載程式碼：$TGDB_DIR"
  git clone --depth=1 --branch "$TGDB_BRANCH" "$REPO_URL" "$TGDB_DIR"
}

start_tgdb() {
  cd "$TGDB_DIR"
  chmod +x tgdb.sh

  log_info "已完成：安裝 git、同步專案、進入目錄與賦予執行權限。"
  if [ "${#TGDB_ARGS[@]}" -gt 0 ]; then
    log_info "正在以 CLI 參數啟動 TGDB：${TGDB_ARGS[*]}"
    exec ./tgdb.sh "${TGDB_ARGS[@]}"
  fi

  log_info "正在啟動 TGDB..."

  if [ -t 0 ] && [ -t 1 ]; then
    exec ./tgdb.sh
  fi

  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    exec ./tgdb.sh < /dev/tty > /dev/tty 2>&1
  fi

  log_warn "偵測到非互動終端，無法直接進入選單。"
  log_info "請手動執行：$TGDB_DIR/tgdb.sh"
}

main() {
  ensure_sudo
  install_git
  sync_project
  start_tgdb
}

main "$@"
