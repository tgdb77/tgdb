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

# Quadlet rootless 單元目錄（*.container / *.network / *.volume ...）
rm_user_units_dir() {
  printf '%s\n' "$(rm_xdg_config_home)/containers/systemd"
}

rm_rootful_root_dir() {
  printf '%s\n' "${TGDB_ROOTFUL_ROOT:-/var/lib/tgdb}"
}

# rootful systemd system 單元目錄（*.service / *.timer）
rm_system_systemd_dir() {
  printf '%s\n' "/etc/systemd/system"
}

# Quadlet rootful 單元目錄（*.container / *.network / *.volume ...）
rm_system_units_dir() {
  printf '%s\n' "/etc/containers/systemd"
}

rm_quadlet_root_dir_by_mode() {
  local mode="${1:-rootless}"
  case "${mode,,}" in
    rootful|system)
      rm_system_units_dir
      ;;
    rootless|user|"")
      rm_user_units_dir
      ;;
    *)
      tgdb_fail "不支援的部署模式：$mode" 1 || return $?
      ;;
  esac
}

rm_tgdb_runtime_quadlet_root_dir_by_mode() {
  local mode="${1:-rootless}"
  printf '%s\n' "$(rm_quadlet_root_dir_by_mode "$mode")/tgdb"
}

rm_service_runtime_quadlet_dir_by_mode() {
  local service="$1" mode="${2:-rootless}"
  _rm_require_safe_segment "$service" "服務名稱" || return 1
  printf '%s\n' "$(rm_tgdb_runtime_quadlet_root_dir_by_mode "$mode")/$service"
}

rm_runtime_quadlet_unit_path_by_mode() {
  local service="$1" filename="$2" mode="${3:-rootless}"
  _rm_require_safe_segment "$service" "服務名稱" || return 1
  _rm_require_safe_segment "$filename" "單元檔名" || return 1
  printf '%s\n' "$(rm_service_runtime_quadlet_dir_by_mode "$service" "$mode")/$filename"
}

rm_legacy_quadlet_unit_path_by_mode() {
  local filename="$1" mode="${2:-rootless}"
  _rm_require_safe_segment "$filename" "單元檔名" || return 1
  printf '%s\n' "$(rm_quadlet_root_dir_by_mode "$mode")/$filename"
}

rm_runtime_or_legacy_quadlet_unit_path_by_mode() {
  local service="$1" filename="$2" mode="${3:-rootless}"
  local runtime_path legacy_path

  runtime_path="$(rm_runtime_quadlet_unit_path_by_mode "$service" "$filename" "$mode" 2>/dev/null || true)"
  if [ -n "$runtime_path" ] && [ -e "$runtime_path" ]; then
    printf '%s\n' "$runtime_path"
    return 0
  fi

  legacy_path="$(rm_legacy_quadlet_unit_path_by_mode "$filename" "$mode" 2>/dev/null || true)"
  if [ -n "$legacy_path" ] && [ -e "$legacy_path" ]; then
    printf '%s\n' "$legacy_path"
    return 0
  fi

  if [ -n "$runtime_path" ]; then
    printf '%s\n' "$runtime_path"
    return 0
  fi
  printf '%s\n' "$legacy_path"
}

_rm_read_file_maybe_privileged() {
  local path="$1"
  [ -n "$path" ] || return 1
  if [ -r "$path" ]; then
    cat "$path"
    return $?
  fi
  if declare -F _tgdb_run_privileged >/dev/null 2>&1; then
    _tgdb_run_privileged cat "$path" 2>/dev/null
    return $?
  fi
  return 1
}

_rm_find_quadlet_files_by_mode() {
  local mode="${1:-rootless}" dir="$2" mindepth="${3:-}" maxdepth="${4:-}"
  [ -n "$dir" ] || return 0

  local -a args=("$dir")
  [ -n "$mindepth" ] && args+=(-mindepth "$mindepth")
  [ -n "$maxdepth" ] && args+=(-maxdepth "$maxdepth")
  args+=(
    \( -type f -o -type l \)
    \(
      -name "*.container" -o
      -name "*.network" -o
      -name "*.volume" -o
      -name "*.pod" -o
      -name "*.device" -o
      -name "*.kube" -o
      -name "*.image"
    \)
    -print
  )

  case "${mode,,}" in
    rootful|system)
      if declare -F _tgdb_run_privileged >/dev/null 2>&1; then
        _tgdb_run_privileged find "${args[@]}" 2>/dev/null
        return $?
      fi
      ;;
  esac

  find "${args[@]}" 2>/dev/null
}

_rm_runtime_quadlet_metadata_field() {
  local path="$1" field="$2"
  _rm_read_file_maybe_privileged "$path" 2>/dev/null | awk -v key="$field" '
    $0 ~ "^[[:space:]]*# *" key "[[:space:]]*:" {
      line=$0
      sub(/^[[:space:]]*# *[^:]+:[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") { print line; exit }
    }
  '
}

_rm_runtime_quadlet_service_from_content() {
  local path="$1"
  local service=""

  service="$(_rm_runtime_quadlet_metadata_field "$path" "TGDB-Service" 2>/dev/null || true)"
  if [ -n "$service" ]; then
    printf '%s\n' "$service"
    return 0
  fi

  _rm_read_file_maybe_privileged "$path" 2>/dev/null | awk '
    /^[[:space:]]*Label[[:space:]]*=/ {
      line=$0
      sub(/^[[:space:]]*Label[[:space:]]*=[[:space:]]*/, "", line)
      sub(/[[:space:]]*(#.*)?$/, "", line)
      gsub(/^"|"$/, "", line)

      n = split(line, parts, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        p = parts[i]
        gsub(/^"|"$/, "", p)
        if (p ~ /^app=/) {
          sub(/^app=/, "", p)
          if (p != "") { print p; exit }
        }
      }
    }
  '
}

_rm_runtime_quadlet_references_tgdb_paths() {
  local path="$1"
  local content=""
  local -a refs=()
  local ref=""

  content="$(_rm_read_file_maybe_privileged "$path" 2>/dev/null || true)"
  [ -n "$content" ] || return 1

  refs+=("$(rm_runtime_app_dir_by_mode rootless 2>/dev/null || true)")
  refs+=("$(rm_runtime_app_dir_by_mode rootful 2>/dev/null || true)")
  refs+=("$(rm_persist_config_dir_by_mode rootless 2>/dev/null || true)")
  refs+=("$(rm_persist_config_dir_by_mode rootful 2>/dev/null || true)")

  for ref in "${refs[@]}"; do
    [ -n "$ref" ] || continue
    case "$content" in
      *"$ref"*)
        return 0
        ;;
    esac
  done
  return 1
}

rm_runtime_quadlet_service_from_path() {
  local path="$1"
  [ -n "$path" ] || return 1

  local mode root rest service
  for mode in rootless rootful; do
    root="$(rm_tgdb_runtime_quadlet_root_dir_by_mode "$mode" 2>/dev/null || true)"
    [ -n "$root" ] || continue
    case "$path" in
      "$root"/*/*)
        rest="${path#"$root"/}"
        service="${rest%%/*}"
        if [ -n "$service" ] && [ "$service" != "$rest" ]; then
          printf '%s\n' "$service"
          return 0
        fi
        ;;
    esac
  done

  service="$(_rm_runtime_quadlet_service_from_content "$path" 2>/dev/null || true)"
  [ -n "$service" ] || return 1
  printf '%s\n' "$service"
}

rm_runtime_quadlet_is_tgdb_managed() {
  local path="$1"
  [ -n "$path" ] || return 1

  local mode root
  for mode in rootless rootful; do
    root="$(rm_tgdb_runtime_quadlet_root_dir_by_mode "$mode" 2>/dev/null || true)"
    [ -n "$root" ] || continue
    case "$path" in
      "$root"/*)
        return 0
        ;;
    esac
  done

  if [ -n "$(_rm_runtime_quadlet_metadata_field "$path" "TGDB-Managed" 2>/dev/null || true)" ]; then
    return 0
  fi
  if [ -n "$(_rm_runtime_quadlet_service_from_content "$path" 2>/dev/null || true)" ]; then
    return 0
  fi
  _rm_runtime_quadlet_references_tgdb_paths "$path"
}

_rm_emit_runtime_quadlet_record() {
  local scope="$1" service="$2" basename="$3" path="$4" managed="${5:-1}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$scope" "$service" "$basename" "$path" "$managed"
}

rm_list_tgdb_runtime_quadlet_files_by_mode() {
  local mode="${1:-rootless}"
  local scope="user"
  case "${mode,,}" in
    rootful|system) scope="system" ;;
  esac

  local runtime_root legacy_root path base service
  runtime_root="$(rm_tgdb_runtime_quadlet_root_dir_by_mode "$mode" 2>/dev/null || true)"
  legacy_root="$(rm_quadlet_root_dir_by_mode "$mode" 2>/dev/null || true)"

  if [ -n "$runtime_root" ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      base="${path##*/}"
      service="$(rm_runtime_quadlet_service_from_path "$path" 2>/dev/null || true)"
      _rm_emit_runtime_quadlet_record "$scope" "$service" "$base" "$path" "1"
    done < <(_rm_find_quadlet_files_by_mode "$mode" "$runtime_root" "1" "2")
  fi

  if [ -n "$legacy_root" ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if ! rm_runtime_quadlet_is_tgdb_managed "$path"; then
        continue
      fi
      base="${path##*/}"
      service="$(rm_runtime_quadlet_service_from_path "$path" 2>/dev/null || true)"
      _rm_emit_runtime_quadlet_record "$scope" "$service" "$base" "$path" "1"
    done < <(_rm_find_quadlet_files_by_mode "$mode" "$legacy_root" "1" "1")
  fi
}

rm_list_service_runtime_quadlet_files_by_mode() {
  local service="$1" mode="${2:-rootless}"
  _rm_require_safe_segment "$service" "服務名稱" || return 1

  local scope="user"
  case "${mode,,}" in
    rootful|system) scope="system" ;;
  esac

  local service_dir legacy_root path base path_service
  service_dir="$(rm_service_runtime_quadlet_dir_by_mode "$service" "$mode" 2>/dev/null || true)"
  legacy_root="$(rm_quadlet_root_dir_by_mode "$mode" 2>/dev/null || true)"

  if [ -n "$service_dir" ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      base="${path##*/}"
      _rm_emit_runtime_quadlet_record "$scope" "$service" "$base" "$path" "1"
    done < <(_rm_find_quadlet_files_by_mode "$mode" "$service_dir" "1" "1")
  fi

  if [ -n "$legacy_root" ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if ! rm_runtime_quadlet_is_tgdb_managed "$path"; then
        continue
      fi
      path_service="$(rm_runtime_quadlet_service_from_path "$path" 2>/dev/null || true)"
      [ "$path_service" = "$service" ] || continue
      base="${path##*/}"
      _rm_emit_runtime_quadlet_record "$scope" "$service" "$base" "$path" "1"
    done < <(_rm_find_quadlet_files_by_mode "$mode" "$legacy_root" "1" "1")
  fi
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
