#!/bin/bash

# TGDB 路徑/紀錄管理（供各模組共用）
# 目的：集中管理 PERSIST_CONFIG_DIR 與 Quadlet user units 路徑，避免多處硬編碼。
# 注意：此檔案為 library，請勿在此更改 shell options（例如 set -e）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_CORE_RECORD_MANAGER_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_RECORD_MANAGER_LOADED=1

_rm_require_nonempty() {
  local v="$1" msg="$2"
  if [ -z "$v" ]; then
    tgdb_fail "$msg" 1 || return $?
  fi
  return 0
}

_rm_require_safe_segment() {
  local seg="$1" what="${2:-參數}"
  _rm_require_nonempty "$seg" "$what 不可為空" || return 1
  case "$seg" in
    */*|*\\*)
      tgdb_fail "$what 不可包含路徑分隔符：$seg" 1 || return $?
      ;;
  esac
  return 0
}

rm_xdg_config_home() {
  if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    printf '%s\n' "$XDG_CONFIG_HOME"
  else
    local home="${TGDB_INVOKING_HOME:-$HOME}"
    printf '%s\n' "$home/.config"
  fi
}

# rootless user systemd 單元目錄（*.timer / *.service ...）
rm_user_systemd_dir() {
  printf '%s\n' "$(rm_xdg_config_home)/systemd/user"
}

rm_user_systemd_unit_path() {
  local filename="$1"
  _rm_require_safe_segment "$filename" "單元檔名" || return 1
  printf '%s\n' "$(rm_user_systemd_dir)/$filename"
}

# Quadlet rootless 單元目錄（*.container / *.network / *.volume ...）
rm_user_units_dir() {
  printf '%s\n' "$(rm_xdg_config_home)/containers/systemd"
}

rm_user_unit_path() {
  local filename="$1"
  _rm_require_safe_segment "$filename" "單元檔名" || return 1
  printf '%s\n' "$(rm_user_units_dir)/$filename"
}

rm_rootful_root_dir() {
  printf '%s\n' "${TGDB_ROOTFUL_ROOT:-/var/lib/tgdb}"
}

# rootful systemd system 單元目錄（*.service / *.timer）
rm_system_systemd_dir() {
  printf '%s\n' "/etc/systemd/system"
}

rm_system_systemd_unit_path() {
  local filename="$1"
  _rm_require_safe_segment "$filename" "單元檔名" || return 1
  printf '%s\n' "$(rm_system_systemd_dir)/$filename"
}

# Quadlet rootful 單元目錄（*.container / *.network / *.volume ...）
rm_system_units_dir() {
  printf '%s\n' "/etc/containers/systemd"
}

rm_system_unit_path() {
  local filename="$1"
  _rm_require_safe_segment "$filename" "單元檔名" || return 1
  printf '%s\n' "$(rm_system_units_dir)/$filename"
}

rm_persist_config_dir() {
  local dir="${PERSIST_CONFIG_DIR:-}"
  _rm_require_nonempty "$dir" "PERSIST_CONFIG_DIR 未設定，無法取得持久化設定目錄" || return 1

  # 規則：PERSIST_CONFIG_DIR 視為「持久化根目錄」，設定檔/紀錄統一放在 $PERSIST_CONFIG_DIR/config。
  if [ "$(basename "$dir")" = "config" ]; then
    local parent
    parent="$(dirname "$dir")"
    tgdb_fail "PERSIST_CONFIG_DIR 不應指向 .../config（已移除舊版相容），請改設為持久化根目錄：$parent" 1 || return $?
  fi

  printf '%s\n' "$dir/config"
}

rm_persist_config_dir_by_mode() {
  local mode="${1:-rootless}"
  case "${mode,,}" in
    rootful|system)
      printf '%s\n' "$(rm_rootful_root_dir)/config"
      ;;
    rootless|user|"")
      rm_persist_config_dir
      ;;
    *)
      tgdb_fail "不支援的部署模式：$mode" 1 || return $?
      ;;
  esac
}

rm_runtime_app_dir_by_mode() {
  local mode="${1:-rootless}"
  case "${mode,,}" in
    rootful|system)
      printf '%s\n' "$(rm_rootful_root_dir)/app"
      ;;
    rootless|user|"")
      _rm_require_nonempty "${TGDB_DIR:-}" "TGDB_DIR 未設定，無法取得應用資料目錄" || return 1
      printf '%s\n' "$TGDB_DIR"
      ;;
    *)
      tgdb_fail "不支援的部署模式：$mode" 1 || return $?
      ;;
  esac
}

rm_persist_timer_dir() {
  printf '%s\n' "$(rm_persist_config_dir)/timer"
}

rm_persist_timer_dir_by_mode() {
  local mode="${1:-rootless}"
  printf '%s\n' "$(rm_persist_config_dir_by_mode "$mode")/timer"
}

rm_service_dir() {
  local service="$1"
  _rm_require_safe_segment "$service" "服務名稱" || return 1
  printf '%s\n' "$(rm_persist_config_dir)/$service"
}

rm_service_configs_dir() {
  local service="$1"
  printf '%s\n' "$(rm_service_dir "$service")/configs"
}

rm_service_quadlet_dir() {
  local service="$1"
  printf '%s\n' "$(rm_service_dir "$service")/quadlet"
}

rm_service_dir_by_mode() {
  local service="$1" mode="${2:-rootless}"
  _rm_require_safe_segment "$service" "服務名稱" || return 1
  printf '%s\n' "$(rm_persist_config_dir_by_mode "$mode")/$service"
}

rm_service_configs_dir_by_mode() {
  local service="$1" mode="${2:-rootless}"
  printf '%s\n' "$(rm_service_dir_by_mode "$service" "$mode")/configs"
}

rm_service_quadlet_dir_by_mode() {
  local service="$1" mode="${2:-rootless}"
  printf '%s\n' "$(rm_service_dir_by_mode "$service" "$mode")/quadlet"
}

rm_persist_quadlet_dir() {
  printf '%s\n' "$(rm_persist_config_dir)/quadlet"
}

rm_quadlet_subdir_by_ext() {
  local ext="$1"
  case "$ext" in
    container) printf '%s\n' "containers" ;;
    network) printf '%s\n' "networks" ;;
    volume) printf '%s\n' "volumes" ;;
    pod) printf '%s\n' "pods" ;;
    device) printf '%s\n' "devices" ;;
    *) return 1 ;;
  esac
}

rm_persist_quadlet_subdir_dir() {
  local sub="$1"
  _rm_require_safe_segment "$sub" "子目錄" || return 1
  printf '%s\n' "$(rm_persist_quadlet_dir)/$sub"
}

rm_persist_quadlet_dir_by_ext() {
  local ext="$1"
  local sub
  sub="$(rm_quadlet_subdir_by_ext "$ext")" || return 1
  rm_persist_quadlet_subdir_dir "$sub"
}
