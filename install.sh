#!/usr/bin/env bash

set -euo pipefail

REPO_URL="${TGDB_REPO_URL:-https://github.com/tgdb77/tgdb.git}"
TGDB_BRANCH="${TGDB_BRANCH:-main}"
TGDB_ARGS=("$@")
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

has_interactive_tty() {
  ( : < /dev/tty > /dev/tty ) 2>/dev/null
}

ensure_interactive_tty() {
  if ! has_interactive_tty; then
    log_error "目前無法存取互動終端，不能建立或切換普通管理員用戶。"
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

  if has_interactive_tty; then
    # sudo 預設會自行從控制終端讀取密碼，不需要重新導向標準輸入。
    if ! sudo -v; then
      log_error "sudo 權限驗證失敗，請確認目前用戶的 sudo 規則與密碼。"
      exit 1
    fi
  elif ! sudo -n true >/dev/null 2>&1; then
    log_error "無法以非互動模式取得 sudo 權限，且沒有可用的互動終端可輸入密碼。"
    log_error "請在互動終端中重新執行；切換用戶時須保留或建立可用的控制終端。"
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

is_usable_admin_user() {
  local username="$1"
  local passwd_entry=""
  local uid=""
  local home_dir=""
  local login_shell=""

  passwd_entry="$(getent passwd "$username")" || return 1
  IFS=: read -r _ _ uid _ _ home_dir login_shell <<< "$passwd_entry"

  [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" -ne 0 ] || return 1
  [ -n "$home_dir" ] && [ -d "$home_dir" ] || return 1
  [ -n "$login_shell" ] && [ -x "$login_shell" ] || return 1
  case "${login_shell##*/}" in
    nologin|false) return 1 ;;
  esac

  # 以 sudo 實際規則判定，涵蓋 sudo/wheel 群組與個別 sudoers 設定。
  sudo -n -l -U "$username" >/dev/null 2>&1
}

find_existing_admin_user() {
  local username=""
  local uid=""
  local uid_min=""
  local uid_max=""

  # 透過 sudo 啟動時，優先切回原始操作者，但仍須確認帳號可登入且具 sudo 權限。
  if [ -n "${SUDO_USER:-}" ] && is_usable_admin_user "$SUDO_USER"; then
    printf '%s\n' "$SUDO_USER"
    return 0
  fi

  if [ -r /etc/login.defs ]; then
    uid_min="$(awk '$1 == "UID_MIN" {print $2; exit}' /etc/login.defs)"
    uid_max="$(awk '$1 == "UID_MAX" {print $2; exit}' /etc/login.defs)"
  fi
  [[ "$uid_min" =~ ^[0-9]+$ ]] || uid_min=1000
  [[ "$uid_max" =~ ^[0-9]+$ ]] || uid_max=60000

  # 僅掃描普通用戶 UID 範圍，避免誤選服務帳號。
  while IFS=: read -r username _ uid _ _ _ _; do
    [[ "$uid" =~ ^[0-9]+$ ]] || continue
    if [ "$uid" -lt "$uid_min" ] || [ "$uid" -gt "$uid_max" ]; then
      continue
    fi
    if is_usable_admin_user "$username"; then
      printf '%s\n' "$username"
      return 0
    fi
  done < <(getent passwd)

  return 1
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

write_installer_snapshot() {
  local output_file="$1"

  # 由已載入的函式與設定產生實體安裝器，避免重讀已消耗的 curl 管線或 /dev/fd。
  # 明確列出本安裝器的函式，避免將呼叫環境中的其他函式一併帶入。
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    declare -p REPO_URL TGDB_BRANCH
    printf '%s\n' \
      'TGDB_ARGS=("$@")' \
      "TGDB_PARENT_DIR=\"\${TGDB_PARENT_DIR:-}\"" \
      'TGDB_DIR=""' \
      'SUDO_CMD=""'
    declare -f \
      log_info log_warn log_error get_admin_group init_paths is_valid_username \
      has_interactive_tty ensure_interactive_tty install_package_as_root \
      ensure_sudo_available_for_user ensure_sudo_installed_as_root \
      is_usable_admin_user find_existing_admin_user create_admin_user_as_root \
      write_installer_snapshot switch_to_user_login ensure_normal_admin_runner \
      install_git sync_project start_tgdb main
    printf '\nmain "$@"\n'
  } > "$output_file"
}

switch_to_user_login() {
  local target_user="$1"
  local target_home=""
  local target_uid=""
  local target_gid=""
  local temp_dir=""
  local temp_script=""
  local bash_path=""
  local runtime_dir=""
  local login_command=""
  local shell_command=""
  local switch_status=0
  local env_args=()
  local shell_env_args=()

  ensure_interactive_tty
  if ! command -v su >/dev/null 2>&1; then
    log_error "找不到 su，無法切換至 '$target_user' 的登入環境。"
    exit 1
  fi
  if ! su --help 2>&1 | grep -q -- '--pty'; then
    log_error "目前的 su 不支援 --pty，無法提供自動續跑安裝所需的互動終端。"
    log_error "請安裝支援 --pty 的 su（util-linux），或先手動 su - $target_user 後再執行安裝指令。"
    exit 1
  fi

  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
    log_error "找不到用戶 '$target_user' 的家目錄，無法繼續安裝。"
    exit 1
  fi
  target_uid="$(id -u "$target_user")"
  target_gid="$(id -g "$target_user")"
  bash_path="$(command -v bash)"
  runtime_dir="/run/user/$target_uid"

  temp_dir="$(mktemp -d /tmp/tgdb-install.XXXXXX)"
  trap 'rm -rf -- "$temp_dir"' EXIT
  temp_script="$temp_dir/install.sh"
  write_installer_snapshot "$temp_script"
  chmod 600 "$temp_script"
  chmod 700 "$temp_dir"
  chown "$target_uid:$target_gid" "$temp_script" "$temp_dir"

  env_args=("TGDB_INSTALL_SWITCHED=1" "TGDB_PARENT_DIR=${TGDB_PARENT_DIR:-$target_home}")
  if [ -d "$runtime_dir" ]; then
    shell_env_args+=("XDG_RUNTIME_DIR=$runtime_dir")
    if [ -S "$runtime_dir/bus" ]; then
      shell_env_args+=("DBUS_SESSION_BUS_ADDRESS=unix:path=$runtime_dir/bus")
    fi
  fi
  printf -v login_command '%q ' env "${env_args[@]}" "${shell_env_args[@]}" "$bash_path" "$temp_script" "${TGDB_ARGS[@]}"
  printf -v shell_command '%q ' env "${shell_env_args[@]}" "$bash_path" -il
  # 安裝器退出後接續同一用戶的互動登入 shell，不讓 su -c 立即返回 root。
  login_command="${login_command}; exec $shell_command"

  # --pty 為 su -c 建立的新 session 配置控制終端，讓 sudo 可以正常提示密碼。
  # 指定 Bash 登入 shell，確保 %q 產生的命令與原始 CLI 參數可正確解析。
  log_info "即將透過 su --pty - $target_user 登入並自動繼續安裝，sudo 可能要求輸入密碼。"
  log_info "退出 TGDB 後會留在 '$target_user' 的登入 shell；再輸入 exit 才會返回原本的 root shell。"
  if su --pty - "$target_user" -s "$bash_path" -c "$login_command" < /dev/tty > /dev/tty 2>&1; then
    switch_status=0
  else
    switch_status=$?
  fi
  exit "$switch_status"
}

ensure_normal_admin_runner() {
  local target_user=""

  if [ "$(id -u)" -ne 0 ]; then
    ensure_sudo_available_for_user
    return 0
  fi

  if [ "${TGDB_INSTALL_SWITCHED:-0}" = "1" ]; then
    log_error "切換用戶後仍為 root，已停止安裝；請確認 su 與目標帳號設定。"
    exit 1
  fi

  ensure_interactive_tty
  ensure_sudo_installed_as_root

  if target_user="$(find_existing_admin_user)"; then
    log_info "偵測到具 sudo 權限的普通用戶 '$target_user'，將切換至該用戶並自動繼續安裝。"
  else
    log_warn "未偵測到可登入且具 sudo 權限的普通用戶，將建立新的普通管理員用戶。"
    target_user="$(create_admin_user_as_root)"
  fi

  switch_to_user_login "$target_user"
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

  if has_interactive_tty; then
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
