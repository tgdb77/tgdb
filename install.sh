#!/usr/bin/env bash

set -euo pipefail

REPO_URL="${TGDB_REPO_URL:-https://github.com/tgdb77/tgdb.git}"
TGDB_BRANCH="${TGDB_BRANCH:-main}"
TGDB_ARGS=("$@")
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
TGDB_PARENT_DIR="${TGDB_PARENT_DIR:-}"
TGDB_DIR=""
SUDO_CMD=""

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

get_admin_group() {
  if getent group sudo >/dev/null 2>&1; then
    echo "sudo"
    return 0
  fi

  if getent group wheel >/dev/null 2>&1; then
    echo "wheel"
    return 0
  fi

  echo "sudo"
}

init_paths() {
  if [ -z "$TGDB_PARENT_DIR" ]; then
    local current_dir
    current_dir="$(pwd 2>/dev/null || true)"
    if [ -n "$current_dir" ] && [ -d "$current_dir" ] && [ -w "$current_dir" ]; then
      TGDB_PARENT_DIR="$current_dir"
    elif [ -n "${HOME:-}" ] && [ -d "${HOME:-}" ]; then
      TGDB_PARENT_DIR="$HOME"
    else
      TGDB_PARENT_DIR="/tmp"
    fi
  fi

  TGDB_DIR="$TGDB_PARENT_DIR/tgdb"
}

is_valid_username() {
  [[ "$1" =~ ^[a-z][a-z0-9_-]*$ ]]
}

ensure_interactive_tty() {
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    log_error "目前無法存取互動終端，不能建立普通管理員用戶。"
    log_error "請改在可互動的終端機中執行此安裝腳本。"
    exit 1
  fi
}

install_package_as_root() {
  local package_name="$1"

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y "$package_name"
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    dnf install -y "$package_name"
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    yum install -y "$package_name"
    return 0
  fi

  if command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install "$package_name"
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm "$package_name"
    return 0
  fi

  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$package_name"
    return 0
  fi

  log_error "找不到支援的套件管理器，無法安裝：$package_name"
  exit 1
}

ensure_sudo_available_for_user() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=""
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    log_error "此腳本需要由具 sudo 權限的普通用戶執行，但系統尚未安裝 sudo。"
    log_error "請改用 root 執行本腳本，以便自動建立符合條件的用戶。"
    exit 1
  fi

  if ! sudo -v; then
    log_error "目前用戶無法取得 sudo 權限，請改用具 sudo 權限的普通用戶執行。"
    exit 1
  fi

  SUDO_CMD="sudo"
}

ensure_sudo_installed_as_root() {
  if command -v sudo >/dev/null 2>&1; then
    return 0
  fi

  log_info "未偵測到 sudo，正在以 root 身分安裝 sudo..."
  install_package_as_root "sudo"
}

create_admin_user_as_root() {
  local username=""
  local password=""
  local password_confirm=""
  local admin_group=""
  local sudoers_file=""

  ensure_interactive_tty
  admin_group="$(get_admin_group)"

  while true; do
    read -r -p "請輸入要建立的普通管理員用戶名稱: " username < /dev/tty

    if [ -z "$username" ]; then
      log_warn "用戶名稱不可為空，請重新輸入。"
      continue
    fi

    if ! is_valid_username "$username"; then
      log_warn "用戶名稱格式無效，必須以小寫字母開頭，且只能包含小寫字母、數字、底線與連字號。"
      continue
    fi

    if id "$username" >/dev/null 2>&1; then
      log_warn "用戶 '$username' 已存在，請改用其他名稱。"
      continue
    fi

    break
  done

  while true; do
    read -r -s -p "請輸入 $username 的登入密碼: " password < /dev/tty
    echo > /dev/tty
    read -r -s -p "請再次輸入密碼: " password_confirm < /dev/tty
    echo > /dev/tty

    if [ -z "$password" ]; then
      log_warn "密碼不可為空，請重新輸入。"
      continue
    fi

    if [ "$password" != "$password_confirm" ]; then
      log_warn "兩次輸入的密碼不一致，請重新輸入。"
      continue
    fi

    break
  done

  useradd -m -s /bin/bash "$username"

  if getent group "$admin_group" >/dev/null 2>&1; then
    usermod -aG "$admin_group" "$username"
  fi

  printf '%s:%s\n' "$username" "$password" | chpasswd

  mkdir -p /etc/sudoers.d
  sudoers_file="/etc/sudoers.d/90-tgdb-${username}"
  printf '%s ALL=(ALL:ALL) ALL\n' "$username" > "$sudoers_file"
  chmod 440 "$sudoers_file"

  if command -v visudo >/dev/null 2>&1 && ! visudo -cf "$sudoers_file" >/dev/null 2>&1; then
    rm -f "$sudoers_file"
    log_error "建立 sudo 權限設定失敗，請檢查 sudoers 設定。"
    exit 1
  fi

  log_info "已建立具 sudo 權限的普通用戶：$username" >&2
  printf '%s\n' "$username"
}

reexec_as_user() {
  local target_user="$1"
  local target_home=""
  local temp_script=""

  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
    log_error "找不到用戶 '$target_user' 的家目錄，無法切換執行。"
    exit 1
  fi

  temp_script="$(mktemp /tmp/tgdb-install.XXXXXX.sh)"
  cat "$SCRIPT_SOURCE" > "$temp_script"
  chmod 755 "$temp_script"
  chown "$target_user":"$target_user" "$temp_script" 2>/dev/null || true

  log_info "即將切換至普通管理員用戶 '$target_user' 繼續安裝..."
  exec sudo -H -u "$target_user" \
    env TGDB_INSTALL_SWITCHED=1 TGDB_PARENT_DIR="$target_home" TGDB_REPO_URL="$REPO_URL" TGDB_BRANCH="$TGDB_BRANCH" \
    bash "$temp_script" "${TGDB_ARGS[@]}"
}

ensure_normal_admin_runner() {
  if [ "${TGDB_INSTALL_SWITCHED:-0}" = "1" ]; then
    ensure_sudo_available_for_user
    return 0
  fi

  if [ "$(id -u)" -ne 0 ]; then
    ensure_sudo_available_for_user
    return 0
  fi

  ensure_sudo_installed_as_root

  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    log_info "偵測到原始操作者為普通用戶 '$SUDO_USER'，將切換回該用戶後再繼續安裝。"
    reexec_as_user "$SUDO_USER"
  fi

  local created_user=""

  log_warn "偵測到目前由 root 直接執行，TGDB 需由具 sudo 權限的普通用戶安裝與操作。"
  created_user="$(create_admin_user_as_root)"
  reexec_as_user "$created_user"
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
  ensure_normal_admin_runner
  init_paths
  install_git
  sync_project
  start_tgdb
}

main "$@"
