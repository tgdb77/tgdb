#!/bin/bash

# TGDB AppSpec（宣告式部署規格）讀取器
# 目的：
# - 從 config/<service>/app.spec 讀取 key=value
# - 提供查詢介面，讓 Apps 子系統以 spec 驅動部署流程
#
# 注意：
# - 本檔案為 library，會被 source；請勿在此更改 shell options（例如 set -euo pipefail）。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_APPS_APP_SPEC_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_APPS_APP_SPEC_LOADED=1

# shellcheck source=src/core/bootstrap.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/bootstrap.sh"

declare -Ag TGDB_APP_SPEC=()
declare -Ag TGDB_APP_SPEC_SERVICES=()
declare -Ag TGDB_APP_SPEC_PATHS=()

_appspec_key_is_valid() {
  [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]
}

appspec_has_service() {
  local service="$1"
  [ -n "${service:-}" ] || return 1
  [ -n "${TGDB_APP_SPEC_SERVICES[$service]+x}" ]
}

_appspec_service_loaded() {
  local service="$1"
  [ "${TGDB_APP_SPEC["$service:__loaded"]:-0}" = "1" ]
}

_appspec_ensure_service_loaded() {
  local service="$1"
  appspec_has_service "$service" || return 1
  _appspec_service_loaded "$service" && return 0

  local path="${TGDB_APP_SPEC_PATHS[$service]:-}"
  [ -n "$path" ] || return 1
  [ -f "$path" ] || return 1

  appspec_load_file "$service" "$path"
}

appspec_get_all() {
  local service="$1" key="$2"
  [ -n "${service:-}" ] || return 1
  [ -n "${key:-}" ] || return 1
  _appspec_ensure_service_loaded "$service" || return 1

  local k="${service}:${key}"
  if [ -n "${TGDB_APP_SPEC[$k]+x}" ]; then
    printf '%s\n' "${TGDB_APP_SPEC[$k]}"
    return 0
  fi
  return 1
}

appspec_get() {
  local service="$1" key="$2" default="${3:-}"
  [ -n "${service:-}" ] || { printf '%s\n' "$default"; return 0; }
  [ -n "${key:-}" ] || { printf '%s\n' "$default"; return 0; }
  if ! _appspec_ensure_service_loaded "$service"; then
    printf '%s\n' "$default"
    return 0
  fi

  local k="${service}:${key}"
  if [ -n "${TGDB_APP_SPEC[$k]+x}" ]; then
    local v="${TGDB_APP_SPEC[$k]}"
    v="${v%%$'\n'*}"
    printf '%s\n' "$v"
    return 0
  fi

  printf '%s\n' "$default"
  return 0
}

appspec_list_services() {
  local -a services=()
  local s
  for s in "${!TGDB_APP_SPEC_SERVICES[@]}"; do
    [ -n "$s" ] && services+=("$s")
  done
  [ ${#services[@]} -eq 0 ] && return 0
  printf '%s\n' "${services[@]}" | LC_ALL=C sort -u
}

_appspec_first_value() {
  local service="$1" key="$2"
  local v="${TGDB_APP_SPEC["$service:$key"]:-}"
  printf '%s\n' "${v%%$'\n'*}"
}

_appspec_is_valid_v1_common() {
  local service="$1"
  appspec_has_service "$service" || return 1
  _appspec_ensure_service_loaded "$service" || return 1

  local spec_version base_port quadlet_type
  spec_version="$(_appspec_first_value "$service" "spec_version")"
  [ "$spec_version" = "1" ] || return 1

  base_port="$(_appspec_first_value "$service" "base_port")"
  [[ "$base_port" =~ ^[0-9]+$ ]] || return 1

  quadlet_type="$(_appspec_first_value "$service" "quadlet_type")"
  case "$quadlet_type" in
    single|multi) ;;
    *) return 1 ;;
  esac

  return 0
}

_appspec_has_unit_template_defs() {
  local service="$1"
  local raw
  raw="${TGDB_APP_SPEC["$service:unit"]:-}"
  [ -n "$raw" ] || return 1

  local line
  while IFS= read -r line; do
    case "$line" in
      *template=*)
        return 0
        ;;
    esac
  done <<< "$raw"

  return 1
}

appspec_is_valid_v1_single() {
  local service="$1"
  _appspec_is_valid_v1_common "$service" || return 1

  local quadlet_type quadlet_template
  quadlet_type="$(_appspec_first_value "$service" "quadlet_type")"
  [ "$quadlet_type" = "single" ] || return 1

  quadlet_template="$(_appspec_first_value "$service" "quadlet_template")"
  [ -n "$quadlet_template" ] || return 1

  return 0
}

appspec_is_valid_v1_multi() {
  local service="$1"
  _appspec_is_valid_v1_common "$service" || return 1

  local quadlet_type
  quadlet_type="$(_appspec_first_value "$service" "quadlet_type")"
  [ "$quadlet_type" = "multi" ] || return 1

  # 最小檢查：至少存在一條 unit 定義，且包含 template=
  _appspec_has_unit_template_defs "$service" || return 1

  return 0
}

appspec_is_valid_v1() {
  local service="$1"
  appspec_is_valid_v1_single "$service" && return 0
  appspec_is_valid_v1_multi "$service" && return 0
  return 1
}

appspec_load_file() {
  local service="$1" path="$2"
  [ -n "${service:-}" ] || return 1
  [ -n "${path:-}" ] || return 1
  [ -f "$path" ] || return 1

  local line key value k
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ""|\#*) continue ;;
    esac

    if [[ "$line" != *"="* ]]; then
      tgdb_warn "忽略無效 AppSpec 行（缺少 '='）：$path：$line"
      continue
    fi

    key="${line%%=*}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    value="${line#*=}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [ -z "$key" ]; then
      tgdb_warn "忽略無效 AppSpec 行（key 為空）：$path：$line"
      continue
    fi
    if ! _appspec_key_is_valid "$key"; then
      tgdb_warn "忽略無效 AppSpec key：$path：$key"
      continue
    fi

    k="${service}:${key}"
    if [ -n "${TGDB_APP_SPEC[$k]+x}" ]; then
      TGDB_APP_SPEC["$k"]+=$'\n'"$value"
    else
      TGDB_APP_SPEC["$k"]="$value"
    fi
  done <"$path"

  TGDB_APP_SPEC["$service:__loaded"]=1

  return 0
}

appspec_index_all() {
  TGDB_APP_SPEC_SERVICES=()
  TGDB_APP_SPEC_PATHS=()

  [ -d "${CONFIG_DIR:-}" ] || return 0

  local spec_file service
  while IFS= read -r -d $'\0' spec_file; do
    service="${spec_file%/app.spec}"
    service="${service##*/}"
    [ -z "$service" ] && continue
    TGDB_APP_SPEC_SERVICES["$service"]=1
    TGDB_APP_SPEC_PATHS["$service"]="$spec_file"
  done < <(find "$CONFIG_DIR" -maxdepth 2 -type f -name "app.spec" -print0 2>/dev/null)

  return 0
}

# 載入時只先建立索引；各服務內容在首次查詢時才載入（lazy load）。
appspec_index_all || true
