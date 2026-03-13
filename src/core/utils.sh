#!/bin/bash

# TGDB 共用工具模組
# 包含所有 TGDB 腳本共用的工具函式
#
# 注意：此檔案為 library，會被 tgdb.sh 與各模組 source。
# 請勿在此更改 shell options（例如 set -euo pipefail）；由入口層統一控制。

# 載入守衛：避免重複 source 造成函式/變數被覆寫或重複初始化
# 若需要「更新後重新載入」（例如 tgdb.sh 更新後呼叫 load_modules），可暫時設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_CORE_UTILS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_UTILS_LOADED=1

# -------------------------
# 統一錯誤處理（共用介面）
# -------------------------
#
# 設計原則：
# - Library 函式：回傳非 0 代表失敗（不在函式內 exit）。
# - 入口層（tgdb.sh / 各獨立腳本）：負責把 return code 轉換為 exit code 與使用者互動提示。
#
# 備註：現有程式仍可能直接 echo 錯誤訊息；此介面提供「一致做法」以便逐步收斂。

# shellcheck disable=SC2034 # 供入口或模組讀取
TGDB_LAST_ERROR_MSG="${TGDB_LAST_ERROR_MSG:-}"
# shellcheck disable=SC2034 # 供入口或模組讀取
TGDB_LAST_ERROR_CODE="${TGDB_LAST_ERROR_CODE:-0}"
# shellcheck disable=SC2034 # 供入口或模組判斷是否已輸出
TGDB_LAST_ERROR_PRINTED="${TGDB_LAST_ERROR_PRINTED:-0}"

tgdb_set_last_error() {
  local msg="${1:-}"
  local rc="${2:-1}"
  TGDB_LAST_ERROR_MSG="$msg"
  TGDB_LAST_ERROR_CODE="$rc"
  TGDB_LAST_ERROR_PRINTED=0
  return 0
}

tgdb_clear_last_error() {
  TGDB_LAST_ERROR_MSG=""
  TGDB_LAST_ERROR_CODE=0
  TGDB_LAST_ERROR_PRINTED=0
  return 0
}

tgdb_info() {
  echo "ℹ️ $*"
  return 0
}

tgdb_warn() {
  echo "⚠️ $*" >&2
  return 0
}

tgdb_err() {
  tgdb_set_last_error "$*" 1
  echo "❌ $*" >&2
  TGDB_LAST_ERROR_PRINTED=1
  return 0
}

tgdb_fail() {
  local msg="${1:-}"
  local rc="${2:-1}"
  tgdb_set_last_error "$msg" "$rc"
  echo "❌ $msg" >&2
  TGDB_LAST_ERROR_PRINTED=1
  return "$rc"
}

tgdb_print_last_error() {
  local msg="${TGDB_LAST_ERROR_MSG:-}"
  [ -n "$msg" ] || return 1
  if [ "${TGDB_LAST_ERROR_PRINTED:-0}" = "1" ]; then
    return 0
  fi
  echo "❌ $msg" >&2
  TGDB_LAST_ERROR_PRINTED=1
  return 0
}

_is_safe_username() {
  local u="$1"
  [[ "$u" =~ ^[a-zA-Z0-9._-]+$ ]]
}

_home_by_user() {
  local user="$1"
  [ -z "$user" ] && { echo ""; return 0; }

  if command -v getent >/dev/null 2>&1; then
    local h
    h="$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || true)"
    [ -n "${h:-}" ] && { printf '%s\n' "$h"; return 0; }
  fi

  local h
  h="$(awk -F: -v u="$user" '$1==u{print $6; exit}' /etc/passwd 2>/dev/null || true)"
  [ -n "${h:-}" ] && { printf '%s\n' "$h"; return 0; }

  echo ""
  return 0
}

_detect_invoking_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    if _is_safe_username "$SUDO_USER"; then
      printf '%s\n' "$SUDO_USER"
      return 0
    fi
  fi
  id -un 2>/dev/null || echo ""
  return 0
}

_detect_invoking_home() {
  local user home
  user="$(_detect_invoking_user)"
  home="$(_home_by_user "$user")"

  if [ -z "${home:-}" ]; then
    home="${HOME:-}"
  fi

  if [ -z "${home:-}" ]; then
    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
      home="/root"
    else
      home="/tmp"
    fi
  fi

  printf '%s\n' "$home"
  return 0
}

UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TGDB_REPO_DIR="$(cd "$UTILS_SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$TGDB_REPO_DIR/config"

UTILS_CONFIG_DIR="$CONFIG_DIR/utils"

# 供其他模組引用（apps-p.sh / podman.sh 等）
# shellcheck disable=SC2034
TGDB_INVOKING_USER="${TGDB_INVOKING_USER:-$(_detect_invoking_user)}"
# shellcheck disable=SC2034
TGDB_INVOKING_HOME="${TGDB_INVOKING_HOME:-$(_detect_invoking_home)}"

# PERSIST_CONFIG_DIR：持久化根目錄（預設：$HOME/.tgdb）
# shellcheck disable=SC2034
if [ -z "${PERSIST_CONFIG_DIR:-}" ]; then
  PERSIST_CONFIG_DIR="$TGDB_INVOKING_HOME/.tgdb"
fi

# UI/互動工具（集中模組）
# shellcheck source=src/core/ui.sh
[ -f "$UTILS_SCRIPT_DIR/ui.sh" ] && source "$UTILS_SCRIPT_DIR/ui.sh"

# 路徑/紀錄管理（集中模組）
# shellcheck source=src/core/record_manager.sh
[ -f "$UTILS_SCRIPT_DIR/record_manager.sh" ] && source "$UTILS_SCRIPT_DIR/record_manager.sh"

# user systemd 定時任務單元（集中模組）
# shellcheck source=src/core/timer_units.sh
[ -f "$UTILS_SCRIPT_DIR/timer_units.sh" ] && source "$UTILS_SCRIPT_DIR/timer_units.sh"

# 定時任務統一管理（集中模組）
# shellcheck source=src/timer/common.sh
[ -f "$TGDB_REPO_DIR/src/timer/common.sh" ] && source "$TGDB_REPO_DIR/src/timer/common.sh"
# shellcheck source=src/timer/registry.sh
[ -f "$TGDB_REPO_DIR/src/timer/registry.sh" ] && source "$TGDB_REPO_DIR/src/timer/registry.sh"
# shellcheck source=src/timer/custom.sh
[ -f "$TGDB_REPO_DIR/src/timer/custom.sh" ] && source "$TGDB_REPO_DIR/src/timer/custom.sh"
# shellcheck source=src/timer/healthchecks.sh
[ -f "$TGDB_REPO_DIR/src/timer/healthchecks.sh" ] && source "$TGDB_REPO_DIR/src/timer/healthchecks.sh"
# shellcheck source=src/timer/runner.sh
[ -f "$TGDB_REPO_DIR/src/timer/runner.sh" ] && source "$TGDB_REPO_DIR/src/timer/runner.sh"
# shellcheck source=src/timer/menu.sh
[ -f "$TGDB_REPO_DIR/src/timer/menu.sh" ] && source "$TGDB_REPO_DIR/src/timer/menu.sh"

# utils 設定持久化檔案（預設：$PERSIST_CONFIG_DIR/config/utils/config.conf）
UTILS_PERSIST_DIR="$(rm_persist_config_dir)/utils"
UTILS_PERSIST_CONFIG_FILE="$UTILS_PERSIST_DIR/config.conf"

ensure_utils_persist_config() {
  local repo_default_file="$UTILS_CONFIG_DIR/configs/default.conf"

  [ -f "$UTILS_PERSIST_CONFIG_FILE" ] && return 0
  [ -f "$repo_default_file" ] || return 0

  if mkdir -p "$UTILS_PERSIST_DIR" 2>/dev/null; then
    cp -n "$repo_default_file" "$UTILS_PERSIST_CONFIG_FILE" 2>/dev/null || true
    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
      local persist_cfg_dir
      persist_cfg_dir="$(rm_persist_config_dir)"
      chown "$(_detect_invoking_uid)":"$(_detect_invoking_gid)" "$PERSIST_CONFIG_DIR" "$persist_cfg_dir" "$UTILS_PERSIST_DIR" "$UTILS_PERSIST_CONFIG_FILE" 2>/dev/null || true
    fi
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$UTILS_PERSIST_DIR" 2>/dev/null || true
    sudo cp -n "$repo_default_file" "$UTILS_PERSIST_CONFIG_FILE" 2>/dev/null || true
    local persist_cfg_dir
    persist_cfg_dir="$(rm_persist_config_dir)"
    sudo chown "$(_detect_invoking_uid)":"$(_detect_invoking_gid)" "$PERSIST_CONFIG_DIR" "$persist_cfg_dir" "$UTILS_PERSIST_DIR" "$UTILS_PERSIST_CONFIG_FILE" 2>/dev/null || true
  fi
  return 0
}

_detect_invoking_uid() {
    # 若是透過 sudo 執行，優先使用原始呼叫者；否則用目前使用者。
    if [[ "${SUDO_UID:-}" =~ ^[0-9]+$ ]] && [ "${SUDO_UID:-0}" -gt 0 ] 2>/dev/null; then
        echo "$SUDO_UID"
        return 0
    fi
    id -u 2>/dev/null || echo 0
}

_detect_invoking_gid() {
    # 若是透過 sudo 執行，優先使用原始呼叫者；否則用目前使用者。
    if [[ "${SUDO_GID:-}" =~ ^[0-9]+$ ]] && [ "${SUDO_GID:-0}" -gt 0 ] 2>/dev/null; then
        echo "$SUDO_GID"
        return 0
    fi
    id -g 2>/dev/null || echo 0
}

_read_kv_or_default() {
    local key="$1"
    local file="$2"
    local default_value="$3"

    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "$default_value"
        return 0
    fi

    local value=""
    value="$(
        { grep -m1 "^${key}=" "$file" 2>/dev/null || true; } | cut -d'=' -f2-
    )"
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default_value"
    fi
}

# 從 utils 設定檔載入系統設定
load_system_config() {
    local repo_default_file="$UTILS_CONFIG_DIR/configs/default.conf"

    ensure_utils_persist_config || true

    local config_file=""
    if [ -f "$UTILS_PERSIST_CONFIG_FILE" ]; then
        config_file="$UTILS_PERSIST_CONFIG_FILE"
    elif [ -f "$repo_default_file" ]; then
        config_file="$repo_default_file"
    fi

    local default_tgdb_dir="${PERSIST_CONFIG_DIR}/app"
    TGDB_DIR="$(_read_kv_or_default "tgdb_dir" "$config_file" "$default_tgdb_dir")"
    DIR_PERMISSIONS="$(_read_kv_or_default "dir_permissions" "$config_file" "750")"

    local default_uid default_gid
    default_uid="$(_detect_invoking_uid)"
    default_gid="$(_detect_invoking_gid)"

    SYSTEM_UID="$(_read_kv_or_default "uid" "$config_file" "$default_uid")"
    SYSTEM_GID="$(_read_kv_or_default "gid" "$config_file" "$default_gid")"

    if [[ ! "${SYSTEM_UID:-}" =~ ^[0-9]+$ ]]; then
        SYSTEM_UID="$default_uid"
    fi
    if [[ ! "${SYSTEM_GID:-}" =~ ^[0-9]+$ ]]; then
        SYSTEM_GID="$default_gid"
    fi
}

tgdb_backup_root() {
  # 依 backup.sh 規則：TGDB_BACKUP_ROOT 優先，否則使用 TGDB_DIR 的上層目錄。
  if [ -z "${TGDB_DIR:-}" ] && declare -F load_system_config >/dev/null 2>&1; then
    load_system_config || true
  fi

  if [ -n "${TGDB_BACKUP_ROOT:-}" ]; then
    printf '%s\n' "$TGDB_BACKUP_ROOT"
    return 0
  fi

  if [ -n "${TGDB_DIR:-}" ]; then
    printf '%s\n' "$(dirname "$TGDB_DIR")"
    return 0
  fi

  # 保底：避免在極端情況（未載入系統設定）回傳空值。
  printf '%s\n' "${PERSIST_CONFIG_DIR:-$HOME/.tgdb}"
  return 0
}

# 確保 ${BACKUP_ROOT}/volume/${service}/${name} 作為 volume_dir（部署時使用；預設不納入備份）
ensure_app_volume_dir() {
  local service="$1"
  local name="${2:-}"
  if [ -z "${service:-}" ] || [ -z "${name:-}" ]; then
    tgdb_fail "未提供 service/name，無法建立 volume_dir。" 1 || return $?
  fi
  case "$service" in
    */*|*\\*) tgdb_fail "服務名稱不可包含路徑分隔符：$service" 1 || return $? ;;
  esac
  case "$name" in
    */*|*\\*) tgdb_fail "實例名稱不可包含路徑分隔符：$name" 1 || return $? ;;
  esac

  local backup_root volume_root target_dir
  backup_root="$(tgdb_backup_root)"
  volume_root="$backup_root/volume/$service"
  target_dir="$volume_root/$name"

  if [ -e "$target_dir" ] && [ ! -d "$target_dir" ]; then
    tgdb_fail "volume_dir 不是資料夾：$target_dir" 1 || return $?
  fi
  if ! mkdir -p "$target_dir" 2>/dev/null; then
    tgdb_fail "無法建立 volume_dir：$target_dir（請確認路徑權限）" 1 || return $?
  fi
  if [ ! -d "$target_dir" ]; then
    tgdb_fail "無法建立 volume_dir：$target_dir" 1 || return $?
  fi
  if [ ! -r "$target_dir" ] || [ ! -w "$target_dir" ]; then
    tgdb_fail "目前使用者對 $target_dir 沒有讀寫權限，請調整權限或改用其他目錄。" 1 || return $?
  fi
  printf '%s\n' "$target_dir"
  return 0
}

# 目錄管理（確保 TGDB_DIR 存在並具正確權限）
create_tgdb_dir() {
  local base_dir marker
  base_dir="$(dirname "$TGDB_DIR")"
  marker="$TGDB_DIR/.tgdb_initialized"

  if [ -d "$TGDB_DIR" ] && [ -f "$marker" ]; then
    return 0
  fi

  if mkdir -p "$base_dir" "$TGDB_DIR" 2>/dev/null; then
    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
      chown "$SYSTEM_UID":"$SYSTEM_GID" "$base_dir" 2>/dev/null || true
      chown -R "$SYSTEM_UID":"$SYSTEM_GID" "$TGDB_DIR" 2>/dev/null || true
    fi
    chmod "$DIR_PERMISSIONS" "$TGDB_DIR" 2>/dev/null || true
    touch "$marker" 2>/dev/null || true
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$base_dir" "$TGDB_DIR"
    sudo chown "$SYSTEM_UID":"$SYSTEM_GID" "$base_dir" 2>/dev/null || true
    sudo chown -R "$SYSTEM_UID":"$SYSTEM_GID" "$TGDB_DIR" 2>/dev/null || true
    sudo chmod "$DIR_PERMISSIONS" "$TGDB_DIR" 2>/dev/null || true
    sudo touch "$marker" 2>/dev/null || true
    return 0
  fi

  tgdb_fail "無法建立 TGDB 目錄：$TGDB_DIR（缺少權限且找不到 sudo）" 1 || return $?
}

# 確保以 root 或具 sudo 權限執行（避免部分指令失敗）
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        if ! command -v sudo >/dev/null 2>&1; then
            tgdb_fail "本操作需要 root 或 sudo 權限。" 1 || return $?
        fi
        if ! sudo -v; then
            tgdb_fail "sudo 權限驗證失敗" 1 || return $?
        fi
    fi
    return 0
}

# 嘗試偵測實際 SSH 連接埠，避免上線後鎖死
detect_ssh_port() {
    if command -v sshd >/dev/null 2>&1; then
        local p
        p=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 0 ] && [ "$p" -lt 65536 ]; then
            echo "$p"
            return 0
        fi
    fi
    if [ -f /etc/ssh/sshd_config ]; then
        local p
        p=$(grep -E "^[[:space:]]*Port[[:space:]]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -n1)
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 0 ] && [ "$p" -lt 65536 ]; then
            echo "$p"
            return 0
        fi
    fi
    if [ -d /etc/ssh/sshd_config.d ]; then
        local p
        p=$(grep -E "^[[:space:]]*Port[[:space:]]+" /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | tail -n1)
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 0 ] && [ "$p" -lt 65536 ]; then
            echo "$p"
            return 0
        fi
    fi
    if [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
        echo "$SSH_PORT"
        return 0
    fi
    echo 22
}

get_ipv4_address() {
  # 取得公網 IPv4（透過 ipinfo.io），供各模組顯示用。
  # 注意：此函式會發出網路請求；若 curl 不存在或請求失敗，會回退為本機「對外」IPv4（可能非公網）。
  local ipv4=""

  if command -v curl >/dev/null 2>&1; then
    ipv4="$(
      curl -fsS --connect-timeout 3 --max-time 5 https://ipinfo.io/ip 2>/dev/null \
        | tr -d '\r\n' \
        | head -n1 \
        || true
    )"
    if [[ ! "${ipv4:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      ipv4=""
    fi
  fi

  if [ -z "${ipv4:-}" ] && command -v ip >/dev/null 2>&1; then
    ipv4="$(
      ip -4 route get 1 2>/dev/null | awk '{
        for (i = 1; i <= NF; i++) {
          if ($i == "src") { print $(i + 1); exit }
        }
      }' || true
    )"
    if [ -z "${ipv4:-}" ]; then
      ipv4="$(
        ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d'/' -f1 || true
      )"
    fi
  fi

  if [ -z "${ipv4:-}" ]; then
    ipv4="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi

  [ -z "${ipv4:-}" ] && ipv4="未知"
  printf '%s\n' "$ipv4"
}

_select_editor() {
    local editor_env="${EDITOR-}"
    if [ -n "$editor_env" ] && command -v "$editor_env" >/dev/null 2>&1; then
        echo "$editor_env"
        return 0
    fi
    for e in nano vim vi; do
        if command -v "$e" >/dev/null 2>&1; then
            echo "$e"
            return 0
        fi
    done
    echo ""
    return 1
}

ensure_editor() {
    local editor
    editor=$(_select_editor) || return 1
    export EDITOR="$editor"
    return 0
}

_is_selinux_enforcing() {
  if command -v getenforce >/dev/null 2>&1; then
    [ "$(getenforce 2>/dev/null || echo Disabled)" = "Enforcing" ] && return 0 || return 1
  fi
  if command -v sestatus >/dev/null 2>&1; then
    sestatus 2>/dev/null | grep -q "Current mode: *enforcing" && return 0 || return 1
  fi
  return 1
}

# 尋找下一個可用的端口
_is_port_in_use() {
    local p="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -qE "(^|[^0-9])${p}([^0-9]|$)"
        return $?
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -qE "(^|[^0-9])${p}([^0-9]|$)"
        return $?
    elif command -v lsof >/dev/null 2>&1; then
        lsof -i -P -n 2>/dev/null | grep -qE "(:|\.)${p}([[:space:]]|$)"
        return $?
    fi
    return 1
}

# 參數 $1：起始埠號（例如 9487）
get_next_available_port() {
    local port="$1"
    while _is_port_in_use "$port"; do
        port=$((port + 1))
    done
    echo "$port"
}

prompt_available_port() {
  local label="${1:-對外埠}"
  local default_port="${2:-}"

  if ! ui_is_interactive; then
    tgdb_fail "非互動模式下不可詢問埠號：$label" 2 || return $?
  fi

  local input port
  while true; do
    if [ -n "$default_port" ]; then
      read -r -e -p "${label} (預設: ${default_port}，輸入 0 取消): " input
      port="${input:-$default_port}"
    else
      read -r -e -p "${label} (輸入 0 取消): " port
    fi

    if [ "$port" = "0" ]; then
      return 2
    fi

    if [ -z "$port" ]; then
      tgdb_err "埠號不能為空，請重新輸入。"
      continue
    fi

    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -le 0 ] 2>/dev/null || [ "$port" -gt 65535 ] 2>/dev/null; then
      tgdb_err "無效的埠號，請輸入 1-65535 的整數。"
      continue
    fi

    if _is_port_in_use "$port"; then
      tgdb_err "埠號 $port 已被占用，請重新輸入。"
      continue
    fi

    printf '%s\n' "$port"
    return 0
  done
}

prompt_port_number() {
  local label="${1:-埠號}"
  local default_port="${2:-}"

  if ! ui_is_interactive; then
    tgdb_fail "非互動模式下不可詢問埠號：$label" 2 || return $?
  fi

  local input port
  while true; do
    if [ -n "$default_port" ]; then
      read -r -e -p "${label} (預設: ${default_port}，輸入 0 取消): " input
      port="${input:-$default_port}"
    else
      read -r -e -p "${label} (輸入 0 取消): " port
    fi

    if [ "$port" = "0" ]; then
      return 2
    fi

    if [ -z "$port" ]; then
      tgdb_err "埠號不能為空，請重新輸入。"
      continue
    fi

    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -le 0 ] 2>/dev/null || [ "$port" -gt 65535 ] 2>/dev/null; then
      tgdb_err "無效的埠號，請輸入 1-65535 的整數。"
      continue
    fi

    printf '%s\n' "$port"
    return 0
  done
}

# --- 系統偵測（發行版） ---
# 從 /etc/os-release 讀取鍵值（避免 source 帶來的 shellcheck 警告與副作用）
_os_release_value() {
    local key="$1"
    local file="/etc/os-release"
    if [ ! -r "$file" ]; then
        echo ""; return 0
    fi
    local line
    line=$(grep -m1 -E "^${key}=" "$file" 2>/dev/null | cut -d'=' -f2-)
    if [ -z "$line" ]; then
        echo ""; return 0
    fi
    line="${line%\r}"
    line="${line%\n}"
    if [[ "$line" =~ ^\".*\"$ ]]; then
        line="${line#\"}"
        line="${line%\"}"
    fi
    echo "$line"
}

if [ -z "${OS_ID+x}" ]; then
  OS_ID="$(_os_release_value ID)"
  readonly OS_ID
fi
if [ -z "${OS_ID_LIKE+x}" ]; then
  OS_ID_LIKE="$(_os_release_value ID_LIKE)"
  readonly OS_ID_LIKE
fi
if [ -z "${OS_VERSION_ID+x}" ]; then
  OS_VERSION_ID="$(_os_release_value VERSION_ID)"
  readonly OS_VERSION_ID
fi
if [ -z "${OS_VERSION_CODENAME+x}" ]; then
    _codename="$(_os_release_value VERSION_CODENAME)"
    if [ -z "$_codename" ] && command -v lsb_release >/dev/null 2>&1; then
        _codename=$(lsb_release -sc 2>/dev/null || echo "")
    fi
    readonly OS_VERSION_CODENAME="$_codename"
    unset _codename
fi

_os_matches_id_or_like() {
    local ids_text="${1:-}"
    local likes_text="${2:-}"
    local id="${OS_ID,,}"
    local like=" ${OS_ID_LIKE,,} "
    local token

    for token in $ids_text; do
        [ "$id" = "$token" ] && return 0
    done
    for token in $likes_text; do
        [[ "$like" == *" $token "* ]] && return 0
    done
    return 1
}

is_debian_like() { _os_matches_id_or_like "debian ubuntu linuxmint" "debian ubuntu"; }

is_rhel_like() { _os_matches_id_or_like "rhel centos fedora rocky almalinux amzn ol redhat" "rhel fedora redhat"; }

is_arch_like() { _os_matches_id_or_like "arch manjaro endeavouros artix" "arch"; }

is_alpine() { _os_matches_id_or_like "alpine" ""; }

is_suse_like() { _os_matches_id_or_like "sles suse opensuse opensuse-tumbleweed opensuse-leap" "suse"; }

# 回傳家族：debian/redhat/arch/alpine/suse/unknown
detect_os_family() {
    if is_debian_like; then
        echo "debian"; return 0
    fi
    if is_rhel_like; then
        echo "redhat"; return 0
    fi
    if is_arch_like; then
        echo "arch"; return 0
    fi
    if is_alpine; then
        echo "alpine"; return 0
    fi
    if is_suse_like; then
        echo "suse"; return 0
    fi
    echo "unknown"
}

_pkg_manager_candidates() {
    case "${1:-fallback}" in
        debian) set -- apt-get ;;
        redhat) set -- dnf yum ;;
        arch) set -- pacman ;;
        suse) set -- zypper ;;
        alpine) set -- apk ;;
        *) set -- apt-get dnf yum zypper pacman apk ;;
    esac
    printf '%s\n' "$@"
}

_pkg_manager_key() {
    case "$1" in
        apt-get) echo "apt" ;;
        dnf|yum|zypper|pacman|apk) echo "$1" ;;
        *) return 1 ;;
    esac
}

# 套件管理器偵測（提供給其他模組重用）
detect_pkg_manager() {
    local family pm
    family="$(detect_os_family)"

    for pm in $(_pkg_manager_candidates "$family"); do
        if command -v "$pm" >/dev/null 2>&1; then
            _pkg_manager_key "$pm"
            return 0
        fi
    done
    for pm in $(_pkg_manager_candidates fallback); do
        if command -v "$pm" >/dev/null 2>&1; then
            _pkg_manager_key "$pm"
            return 0
        fi
    done
    echo "unknown"
}

pkg_has_supported_manager() {
    [ "$(detect_pkg_manager)" != "unknown" ]
}

# 以「角色」集中管理跨發行版套件名稱，避免各模組重複 case。
pkg_role_candidates() {
    case "$1:$(detect_os_family)" in
        ssh-client:debian|ssh-client:alpine) set -- "openssh-client" ;;
        ssh-client:redhat) set -- "openssh-clients" ;;
        ssh-client:arch|ssh-client:suse) set -- "openssh" ;;
        polkit-agent:debian) set -- "policykit-1" "polkit" ;;
        polkit-agent:*) set -- "polkit" "policykit-1" ;;
        containers-common:*) set -- "containers-common" ;;
        legacy-firewall:debian) set -- "ufw" "firewalld" "iptables-persistent" "netfilter-persistent" ;;
        legacy-firewall:redhat) set -- "ufw" "firewalld" "iptables-services" ;;
        legacy-firewall:arch|legacy-firewall:alpine|legacy-firewall:suse) set -- "ufw" "firewalld" ;;
        *) return 1 ;;
    esac
    printf '%s\n' "$@"
}

# shellcheck disable=SC2034 # 供呼叫端讀取「最後成功安裝的候選套件」
TGDB_PKG_LAST_SELECTED="${TGDB_PKG_LAST_SELECTED:-}"

pkg_install_first_available() {
    TGDB_PKG_LAST_SELECTED=""

    local pkg
    for pkg in "$@"; do
        [ -n "$pkg" ] || continue
        if pkg_install "$pkg"; then
            TGDB_PKG_LAST_SELECTED="$pkg"
            return 0
        fi
    done
    return 1
}

pkg_install_role() {
    local role="$1"
    local -a candidates=()

    mapfile -t candidates < <(pkg_role_candidates "$role" 2>/dev/null || true)
    [ ${#candidates[@]} -gt 0 ] || return 1

    pkg_install_first_available "${candidates[@]}"
}

# ---- 套件管理器工具 ----
# 說明：
# - 新版建議使用 pkg_update/pkg_install/pkg_purge/pkg_autoremove... 這類「直接執行」函式。

_tgdb_run_privileged() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi

    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
        "$@"
        return $?
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return $?
    fi

    tgdb_fail "本操作需要 root 權限，且系統未安裝 sudo。" 1 || return $?
}

# shellcheck disable=SC2034 # 供除錯觀察 EPEL 是否已嘗試初始化
TGDB_EPEL_BOOTSTRAPPED="${TGDB_EPEL_BOOTSTRAPPED:-0}"

_os_version_major() {
    local version="${1:-}"
    version="${version%%.*}"
    if [[ "$version" =~ ^[0-9]+$ ]]; then
        echo "$version"
    else
        echo ""
    fi
}

_pkg_should_bootstrap_epel() {
    [ "${TGDB_EPEL_BOOTSTRAPPED:-0}" = "1" ] && return 1

    local manager
    manager="$(detect_pkg_manager)"
    case "$manager" in
        dnf) ;;
        *) return 1 ;;
    esac

    [ "${OS_ID,,}" = "almalinux" ] || return 1

    local major
    major="$(_os_version_major "${OS_VERSION_ID:-}")"
    [ -n "$major" ] || return 1
    [ "$major" -ge 10 ] || return 1

    return 0
}

_pkg_bootstrap_epel() {
    _pkg_should_bootstrap_epel || return 0
    TGDB_EPEL_BOOTSTRAPPED=1

    if command -v rpm >/dev/null 2>&1; then
        if rpm -q epel-release >/dev/null 2>&1; then
            return 0
        fi
    fi

    tgdb_info "偵測到 AlmaLinux ${OS_VERSION_ID:-未知}，自動啟用 EPEL 套件庫..."
    if _tgdb_run_privileged dnf install -y epel-release; then
        echo "✅ 已啟用 EPEL 套件庫（epel-release）"
        return 0
    fi

    tgdb_warn "EPEL 自動啟用失敗，將繼續使用目前套件來源（可能影響 btop 等套件安裝）。"
    return 0
}

_pkg_command_words() {
    case "$(detect_pkg_manager):$1" in
        apt:update) set -- env DEBIAN_FRONTEND=noninteractive apt-get update ;;
        apt:install) set -- env DEBIAN_FRONTEND=noninteractive apt-get install -y ;;
        apt:upgrade) set -- env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y ;;
        apt:clean) set -- apt-get clean ;;
        apt:purge) set -- env DEBIAN_FRONTEND=noninteractive apt-get purge -y ;;
        apt:autoremove) set -- env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y ;;
        dnf:update) set -- dnf -y check-update ;;
        dnf:install) set -- dnf install -y ;;
        dnf:upgrade) set -- dnf upgrade -y ;;
        dnf:clean) set -- dnf clean all ;;
        dnf:purge) set -- dnf remove -y ;;
        dnf:autoremove) set -- dnf -y autoremove ;;
        yum:update) set -- yum -y check-update ;;
        yum:install) set -- yum install -y ;;
        yum:upgrade) set -- yum update -y ;;
        yum:clean) set -- yum clean all ;;
        yum:purge) set -- yum remove -y ;;
        yum:autoremove) set -- yum -y autoremove ;;
        zypper:update) set -- zypper --non-interactive refresh ;;
        zypper:install) set -- zypper --non-interactive in -y ;;
        zypper:upgrade) set -- zypper --non-interactive up -y ;;
        zypper:clean) set -- zypper --non-interactive clean --all ;;
        zypper:purge) set -- zypper --non-interactive rm -y ;;
        zypper:autoremove|apk:autoremove) set -- __noop__ ;;
        pacman:update) set -- pacman -Sy --noconfirm ;;
        pacman:install) set -- pacman -S --noconfirm ;;
        pacman:upgrade) set -- pacman -Syu --noconfirm ;;
        pacman:clean) set -- pacman -Sc --noconfirm ;;
        pacman:purge) set -- pacman -Rns --noconfirm ;;
        apk:update) set -- apk update ;;
        apk:install) set -- apk add ;;
        apk:upgrade) set -- apk upgrade ;;
        apk:clean) set -- apk cache clean ;;
        apk:purge) set -- apk del ;;
        *) return 1 ;;
    esac
    printf '%s\n' "$@"
}

_pkg_action_ignores_failure() {
    case "$(detect_pkg_manager):$1" in
        dnf:update|yum:update|yum:autoremove|pacman:clean|apk:clean) return 0 ;;
        *) return 1 ;;
    esac
}

_pkg_run_action() {
    local action="$1"
    shift

    case "$action" in
        update|install|upgrade) _pkg_bootstrap_epel || true ;;
    esac

    local -a cmd=()
    mapfile -t cmd < <(_pkg_command_words "$action" 2>/dev/null || true)
    [ ${#cmd[@]} -gt 0 ] || return 1
    [ "${cmd[0]}" = "__noop__" ] && return 0

    if _tgdb_run_privileged "${cmd[@]}" "$@"; then
        return 0
    fi

    _pkg_action_ignores_failure "$action" && return 0
    return 1
}

# 套件管理器對外顯示字串（用於互動式說明，避免各模組重複 hardcode）
pkg_action_description() {
    local -a cmd=() filtered=()
    mapfile -t cmd < <(_pkg_command_words "$1" 2>/dev/null || true)
    [ ${#cmd[@]} -gt 0 ] || return 1

    [ "${cmd[0]}" = "__noop__" ] && { echo "(無特別指令，略過)"; return 0; }
    if [ "${cmd[0]}" = "env" ] && [ ${#cmd[@]} -ge 3 ]; then
        cmd=("${cmd[@]:2}")
    fi

    local token
    for token in "${cmd[@]}"; do
        case "$token" in
            -y|--non-interactive|--noconfirm) continue ;;
        esac
        filtered+=("$token")
    done

    local IFS=' '
    printf '%s\n' "${filtered[*]}"
}

pkg_update() {
    _pkg_run_action update
}

pkg_install() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi
    _pkg_run_action install "$@"
}

pkg_upgrade_all() {
    _pkg_run_action upgrade
}

pkg_clean() {
    [ "$(detect_pkg_manager)" = "unknown" ] && return 0
    _pkg_run_action clean
}

pkg_purge() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi
    _pkg_run_action purge "$@"
}

pkg_autoremove() {
    case "$(detect_pkg_manager)" in
        pacman)
            local -a orphans=()
            mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || true)
            [ ${#orphans[@]} -eq 0 ] && return 0
            _tgdb_run_privileged pacman -Rns --noconfirm "${orphans[@]}" || true
            ;;
        unknown) return 0 ;;
        *) _pkg_run_action autoremove ;;
    esac
}

# 使用系統套件管理器安裝套件
install_package() {
    local -a packages=("$@")
    [ ${#packages[@]} -gt 0 ] || return 0

    pkg_update || true
    if ! pkg_install "${packages[@]}"; then
        local IFS=' '
        tgdb_fail "無法識別的包管理器，請手動安裝 ${packages[*]}" 1 || return $?
    fi
}
