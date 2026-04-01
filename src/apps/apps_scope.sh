#!/bin/bash

# Apps：部署模式 / scope / 路徑 / metadata 共用工具
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

TGDB_ROOTLESS_PERSIST_ROOT="${TGDB_ROOTLESS_PERSIST_ROOT:-${PERSIST_CONFIG_DIR:-}}"
TGDB_ROOTLESS_RUNTIME_DIR="${TGDB_ROOTLESS_RUNTIME_DIR:-${TGDB_DIR:-}}"

# shellcheck disable=SC2034 # 供選單與管理流程跨函式讀取
SELECTED_INSTANCE_MODE="${SELECTED_INSTANCE_MODE:-}"
# shellcheck disable=SC2034 # 供紀錄流程跨函式讀取
SELECTED_RECORD_MODE="${SELECTED_RECORD_MODE:-}"

_apps_normalize_deploy_mode() {
  tgdb_normalize_deploy_mode "${1:-rootless}" 2>/dev/null || return 1
}

_apps_scope_for_mode() {
  tgdb_scope_for_deploy_mode "$(_apps_normalize_deploy_mode "${1:-rootless}")" 2>/dev/null || return 1
}

_apps_current_deploy_mode() {
  _apps_normalize_deploy_mode "${TGDB_APPS_ACTIVE_DEPLOY_MODE:-rootless}" 2>/dev/null || printf '%s\n' "rootless"
}

_apps_current_scope() {
  _apps_scope_for_mode "$(_apps_current_deploy_mode)" 2>/dev/null || printf '%s\n' "user"
}

_apps_rootless_persist_root() {
  local base="${TGDB_ROOTLESS_PERSIST_ROOT:-${PERSIST_CONFIG_DIR:-}}"
  [ -n "$base" ] || base="${TGDB_INVOKING_HOME:-$HOME}/.tgdb"
  printf '%s\n' "$base"
}

_apps_rootless_runtime_dir() {
  local dir="${TGDB_ROOTLESS_RUNTIME_DIR:-${TGDB_DIR:-}}"
  if [ -n "$dir" ]; then
    printf '%s\n' "$dir"
    return 0
  fi
  printf '%s\n' "$(_apps_rootless_persist_root)/app"
}

_apps_persist_root_for_mode() {
  local mode
  mode="$(_apps_normalize_deploy_mode "${1:-rootless}")" || return 1
  case "$mode" in
    rootful) rm_rootful_root_dir ;;
    rootless) _apps_rootless_persist_root ;;
  esac
}

_apps_runtime_dir_for_mode() {
  local mode
  mode="$(_apps_normalize_deploy_mode "${1:-rootless}")" || return 1
  case "$mode" in
    rootful) rm_runtime_app_dir_by_mode rootful ;;
    rootless) _apps_rootless_runtime_dir ;;
  esac
}

_apps_instance_dir_for_mode() {
  local mode="$1" name="$2"
  printf '%s\n' "$(_apps_runtime_dir_for_mode "$mode")/$name"
}

_apps_unit_dir_for_mode() {
  local scope
  scope="$(_apps_scope_for_mode "${1:-rootless}")" || return 1
  case "$scope" in
    system) rm_system_units_dir ;;
    user) rm_user_units_dir ;;
  esac
}

_apps_scope_label_for_mode() {
  local scope
  scope="$(_apps_scope_for_mode "${1:-rootless}")" || return 1
  tgdb_scope_label "$scope"
}

_apps_mode_is_rootful() {
  [ "$(_apps_normalize_deploy_mode "${1:-rootless}")" = "rootful" ]
}

_apps_with_deploy_mode() {
  local mode="$1"
  shift || true

  mode="$(_apps_normalize_deploy_mode "$mode")" || return 1
  [ "$#" -gt 0 ] || return 0

  local old_mode="${TGDB_APPS_ACTIVE_DEPLOY_MODE:-}"
  local old_scope="${TGDB_APPS_ACTIVE_SCOPE:-}"
  local old_tgdb_dir="${TGDB_DIR:-}"
  local old_persist_root="${PERSIST_CONFIG_DIR:-}"

  TGDB_APPS_ACTIVE_DEPLOY_MODE="$mode"
  TGDB_APPS_ACTIVE_SCOPE="$(_apps_scope_for_mode "$mode")"
  TGDB_DIR="$(_apps_runtime_dir_for_mode "$mode")"
  PERSIST_CONFIG_DIR="$(_apps_persist_root_for_mode "$mode")"

  "$@"
  local rc=$?

  TGDB_APPS_ACTIVE_DEPLOY_MODE="$old_mode"
  TGDB_APPS_ACTIVE_SCOPE="$old_scope"
  TGDB_DIR="$old_tgdb_dir"
  PERSIST_CONFIG_DIR="$old_persist_root"

  return "$rc"
}

_apps_service_supports_deploy_mode() {
  local service="$1" mode="$2"
  mode="$(_apps_normalize_deploy_mode "$mode")" || return 1

  local raw
  raw="$(appspec_get "$service" "compat_deploy_modes" "")"
  [ -n "$raw" ] || raw="rootless"

  local token normalized
  raw="${raw//,/ }"
  for token in $raw; do
    normalized="$(_apps_normalize_deploy_mode "$token" 2>/dev/null || true)"
    [ -n "$normalized" ] || continue
    [ "$normalized" = "$mode" ] && return 0
  done
  return 1
}

_apps_global_default_deploy_mode() {
  local mode
  mode="$(_apps_normalize_deploy_mode "${TGDB_DEPLOY_MODE_DEFAULT:-rootless}" 2>/dev/null || true)"
  [ -n "$mode" ] || mode="rootless"
  printf '%s\n' "$mode"
}

_apps_service_default_deploy_mode() {
  local service="$1"
  local mode
  mode="$(appspec_get "$service" "deploy_mode_default" "inherit")"

  case "${mode,,}" in
    inherit|"")
      mode="$(_apps_global_default_deploy_mode)"
      ;;
    *)
      mode="$(_apps_normalize_deploy_mode "$mode" 2>/dev/null || true)"
      ;;
  esac

  [ -n "$mode" ] || mode="rootless"
  if ! _apps_service_supports_deploy_mode "$service" "$mode"; then
    # 若指定的 default 模式不支援，回退到可用模式（優先 rootless）。
    if _apps_service_supports_deploy_mode "$service" "rootless"; then
      mode="rootless"
    elif _apps_service_supports_deploy_mode "$service" "rootful"; then
      mode="rootful"
    else
      mode="rootless"
    fi
  fi
  printf '%s\n' "$mode"
}

_apps_resolve_deploy_mode() {
  local service="$1" requested="${2:-}"
  local mode="$requested"

  [ -n "$mode" ] || mode="${TGDB_DEPLOY_MODE:-}"
  if [ -n "$mode" ]; then
    mode="$(_apps_normalize_deploy_mode "$mode" 2>/dev/null || true)"
  else
    mode="$(_apps_service_default_deploy_mode "$service")"
  fi

  [ -n "$mode" ] || mode="rootless"
  if ! _apps_service_supports_deploy_mode "$service" "$mode"; then
    tgdb_fail "應用 '$service' 不支援 ${mode} 部署。" 1 || return $?
    return 1
  fi

  printf '%s\n' "$mode"
}

_apps_prompt_deploy_mode() {
  local service="$1"
  local requested="${2:-}"

  if [ -n "$requested" ] || [ -n "${TGDB_DEPLOY_MODE:-}" ]; then
    _apps_resolve_deploy_mode "$service" "$requested"
    return $?
  fi

  local supports_rootless=0 supports_rootful=0
  _apps_service_supports_deploy_mode "$service" "rootless" && supports_rootless=1
  _apps_service_supports_deploy_mode "$service" "rootful" && supports_rootful=1

  if [ "$supports_rootful" -ne 1 ]; then
    printf '%s\n' "rootless"
    return 0
  fi

  # rootful-only：不需要提示選單，直接使用 rootful。
  if [ "$supports_rootless" -ne 1 ]; then
    if ui_is_interactive; then
      tgdb_warn "此應用僅支援 rootful 佈署：將使用 system scope、可能需要 sudo，且建立後不可直接切換回 rootless。"
    fi
    printf '%s\n' "rootful"
    return 0
  fi

  local default_mode
  default_mode="$(_apps_service_default_deploy_mode "$service")"

  if ! ui_is_interactive; then
    printf '%s\n' "$default_mode"
    return 0
  fi

  while true; do
    echo "部署模式：" >&2
    echo "1. rootless" >&2
    echo "2. rootful" >&2
    echo "0. 取消" >&2

    local default_choice="1"
    [ "$default_mode" = "rootful" ] && default_choice="2"

    read -r -e -p "請輸入選擇 [0-2]（預設: $default_choice）: " choice
    choice="${choice:-$default_choice}"
    case "$choice" in
      1)
        printf '%s\n' "rootless"
        return 0
        ;;
      2)
        tgdb_warn "已選擇 rootful 佈署：將使用 system scope、可能需要 sudo，且建立後不可直接切換回 rootless。"
        printf '%s\n' "rootful"
        return 0
        ;;
      0)
        return 2
        ;;
      *)
        echo "無效選項" >&2
        ;;
    esac
  done
}

_apps_path_exists() {
  local mode="$1" path="$2"
  [ -n "$path" ] || return 1
  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged test -e "$path"
    return $?
  fi
  [ -e "$path" ]
}

_apps_dir_exists() {
  local mode="$1" path="$2"
  [ -n "$path" ] || return 1
  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged test -d "$path"
    return $?
  fi
  [ -d "$path" ]
}

_apps_test() {
  local mode="$1"
  shift || true
  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged test "$@"
    return $?
  fi
  test "$@"
}

_apps_read_file() {
  local mode="$1" path="$2"
  [ -n "$path" ] || return 1
  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged cat "$path"
    return $?
  fi
  cat "$path"
}

_apps_read_first_line() {
  local mode="$1" path="$2"
  local line=""
  while IFS= read -r line; do
    printf '%s\n' "$line"
    return 0
  done < <(_apps_read_file "$mode" "$path" 2>/dev/null || true)
  return 1
}

_apps_mkdir_p() {
  local mode="$1" path="$2"
  [ -n "$path" ] || return 0
  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged mkdir -p "$path"
    return $?
  fi
  mkdir -p "$path"
}

_apps_write_text_file() {
  local mode="$1" path="$2" content="$3"
  local dir
  dir="$(dirname "$path")"
  _apps_mkdir_p "$mode" "$dir" || return 1

  if _apps_mode_is_rootful "$mode"; then
    printf '%s' "$content" | _tgdb_run_privileged tee "$path" >/dev/null
    return $?
  fi

  printf '%s' "$content" >"$path"
}

_apps_copy_file_to_mode() {
  local mode="$1" src="$2" dest="$3"
  _apps_test "$mode" -f "$src" || return 1
  _apps_mkdir_p "$mode" "$(dirname "$dest")" || return 1

  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged cp "$src" "$dest"
    return $?
  fi

  cp "$src" "$dest"
}

_apps_copy_dir_contents_to_mode() {
  local mode="$1" src="$2" dest="$3"
  _apps_test "$mode" -d "$src" || return 0
  _apps_mkdir_p "$mode" "$dest" || return 1

  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged cp -a "$src/." "$dest/"
    return $?
  fi

  cp -a "$src/." "$dest/" 2>/dev/null || cp -r "$src/." "$dest/" 2>/dev/null
}

_apps_remove_file() {
  local mode="$1" path="$2"
  [ -n "$path" ] || return 0
  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged rm -f "$path"
    return $?
  fi
  rm -f "$path"
}

_apps_find_lines() {
  local mode="$1" dir="$2"
  shift 2 || true
  [ -n "$dir" ] || return 0
  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged find "$dir" "$@"
    return $?
  fi
  find "$dir" "$@"
}

_apps_instance_meta_path() {
  local instance_dir="$1"
  printf '%s\n' "$instance_dir/.tgdb_instance_meta"
}

_apps_write_instance_metadata() {
  local service="$1" name="$2" mode="$3" instance_dir="$4"
  local scope runtime_root meta_path content

  mode="$(_apps_normalize_deploy_mode "$mode")" || return 1
  scope="$(_apps_scope_for_mode "$mode")" || return 1
  runtime_root="$(_apps_runtime_dir_for_mode "$mode")"
  meta_path="$(_apps_instance_meta_path "$instance_dir")"

  content=$(
    printf 'service=%s\n' "$service"
    printf 'name=%s\n' "$name"
    printf 'deploy_mode=%s\n' "$mode"
    printf 'scope=%s\n' "$scope"
    printf 'runtime_root=%s\n' "$runtime_root"
    printf 'instance_dir=%s\n' "$instance_dir"
  )

  _apps_write_text_file "$mode" "$meta_path" "$content" || return 1
  if _apps_mode_is_rootful "$mode"; then
    _tgdb_run_privileged chmod 600 "$meta_path" >/dev/null 2>&1 || true
  else
    chmod 600 "$meta_path" 2>/dev/null || true
  fi
}

_apps_instance_exists_in_mode() {
  local name="$1" mode="$2"
  local instance_dir units_dir persist_dir
  instance_dir="$(_apps_instance_dir_for_mode "$mode" "$name")"
  units_dir="$(_apps_unit_dir_for_mode "$mode")"
  persist_dir="$(rm_persist_config_dir_by_mode "$mode" 2>/dev/null || true)"

  if _apps_dir_exists "$mode" "$instance_dir"; then
    return 0
  fi

  if [ -n "$units_dir" ]; then
    if _apps_path_exists "$mode" "$units_dir/$name.container" || \
      _apps_path_exists "$mode" "$units_dir/$name.pod" || \
      _apps_path_exists "$mode" "$units_dir/$name.service" || \
      _apps_path_exists "$mode" "$units_dir/container-$name.service"; then
      return 0
    fi
  fi

  if [ -n "$persist_dir" ]; then
    if _apps_mode_is_rootful "$mode"; then
      if _tgdb_run_privileged find "$persist_dir" -maxdepth 3 -type f \( -path "*/quadlet/$name.container" -o -path "*/quadlet/$name.pod" -o -path "*/configs/$name.*" \) -print -quit 2>/dev/null | grep -q .; then
        return 0
      fi
    else
      if find "$persist_dir" -maxdepth 3 -type f \( -path "*/quadlet/$name.container" -o -path "*/quadlet/$name.pod" -o -path "*/configs/$name.*" \) -print -quit 2>/dev/null | grep -q .; then
        return 0
      fi
    fi
  fi

  return 1
}

_apps_name_exists_any_mode() {
  local name="$1"
  _apps_instance_exists_in_mode "$name" "rootless" && return 0
  _apps_instance_exists_in_mode "$name" "rootful" && return 0
  return 1
}

_apps_detect_instance_deploy_mode() {
  local name="$1" service="${2:-}"
  local has_rootless=0 has_rootful=0

  # 若提供 service，僅檢查其宣告支援的部署模式。
  # 目的：避免在大多數 rootless-only 的 app 流程中，為了偵測/顯示而觸發 sudo 密碼提示。
  if [ -n "$service" ] && declare -F _apps_service_supports_deploy_mode >/dev/null 2>&1; then
    if _apps_service_supports_deploy_mode "$service" "rootless"; then
      _apps_instance_exists_in_mode "$name" "rootless" && has_rootless=1
    fi
    if _apps_service_supports_deploy_mode "$service" "rootful"; then
      _apps_instance_exists_in_mode "$name" "rootful" && has_rootful=1
    fi
  else
    _apps_instance_exists_in_mode "$name" "rootless" && has_rootless=1
    _apps_instance_exists_in_mode "$name" "rootful" && has_rootful=1
  fi

  if [ "$has_rootless" -eq 1 ] && [ "$has_rootful" -eq 1 ]; then
    tgdb_fail "偵測到跨 scope 同名實例：$name，請先人工清理衝突。" 1 || return $?
    return 1
  fi
  if [ "$has_rootful" -eq 1 ]; then
    printf '%s\n' "rootful"
    return 0
  fi
  if [ "$has_rootless" -eq 1 ]; then
    printf '%s\n' "rootless"
    return 0
  fi
  return 1
}
