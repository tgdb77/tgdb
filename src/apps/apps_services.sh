#!/bin/bash

# Apps：服務清單/顯示資訊（由 src/apps-p.sh 載入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

# 服務清單快取（僅限單次腳本執行期間）。
# 目的：避免每次進入「6. 應用程式管理」都重新驗證與排序所有服務。
TGDB_APPS_SERVICES_CACHE_VALID=0
declare -a TGDB_APPS_SERVICES_CACHE=()
TGDB_APPS_SERVICES_CACHE_SCHEMA=1
TGDB_APPS_SERVICES_CACHE_DIR_RESOLVED=""

_apps_services_cache_dir() {
  if [ -n "${TGDB_APPS_SERVICES_CACHE_DIR_RESOLVED:-}" ]; then
    printf '%s\n' "$TGDB_APPS_SERVICES_CACHE_DIR_RESOLVED"
    return 0
  fi

  local base=""
  if declare -F rm_persist_config_dir >/dev/null 2>&1; then
    base="$(rm_persist_config_dir 2>/dev/null || true)"
  else
    base="${PERSIST_CONFIG_DIR:-$HOME/.tgdb}/config"
  fi

  local -a candidates=()
  if [ -n "$base" ]; then
    candidates+=("$base/apps")
  fi
  candidates+=("/tmp/tgdb-cache/apps")

  local dir probe
  for dir in "${candidates[@]}"; do
    mkdir -p "$dir" 2>/dev/null || continue
    probe="$dir/.cache_probe.$$"
    if touch "$probe" 2>/dev/null; then
      rm -f "$probe" 2>/dev/null || true
      TGDB_APPS_SERVICES_CACHE_DIR_RESOLVED="$dir"
      printf '%s\n' "$dir"
      return 0
    fi
  done

  TGDB_APPS_SERVICES_CACHE_DIR_RESOLVED="/tmp/tgdb-cache/apps"
  printf '%s\n' "$TGDB_APPS_SERVICES_CACHE_DIR_RESOLVED"
}

_apps_services_cache_file() {
  printf '%s\n' "$(_apps_services_cache_dir)/services_menu.v${TGDB_APPS_SERVICES_CACHE_SCHEMA}.cache"
}

_apps_services_cache_signature() {
  local payload
  payload="schema=${TGDB_APPS_SERVICES_CACHE_SCHEMA}"
  payload+=$'\n'"config_dir=${CONFIG_DIR:-}"

  local f meta
  for f in "$SRC_DIR/apps/app_spec.sh" "$SRC_DIR/apps/apps_services.sh"; do
    if [ -f "$f" ]; then
      meta="$(stat -c '%Y:%s' "$f" 2>/dev/null || echo "0:0")"
    else
      meta="missing"
    fi
    payload+=$'\n'"file=${f}|${meta}"
  done

  if [ -d "${CONFIG_DIR:-}" ]; then
    local spec_meta
    spec_meta="$(find "$CONFIG_DIR" -maxdepth 2 -type f -name "app.spec" -printf '%P|%s|%T@\n' 2>/dev/null | LC_ALL=C sort)"
    payload+=$'\n'"${spec_meta}"
  fi

  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$payload" | sha1sum | cut -d' ' -f1
    return 0
  fi

  printf '%s' "$payload" | cksum | cut -d' ' -f1-2
}

_apps_services_cache_read() {
  local expected_signature="$1"
  [ -n "$expected_signature" ] || return 1

  local cache_file
  cache_file="$(_apps_services_cache_file)"
  [ -r "$cache_file" ] || return 1

  local first_line=""
  local -a loaded=()
  local line line_no=0

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    if [ "$line_no" -eq 1 ]; then
      first_line="$line"
      continue
    fi
    [ -n "$line" ] && loaded+=("$line")
  done < "$cache_file"

  [ "$first_line" = "signature=${expected_signature}" ] || return 1

  TGDB_APPS_SERVICES_CACHE=("${loaded[@]}")
  TGDB_APPS_SERVICES_CACHE_VALID=1
  return 0
}

_apps_services_cache_write() {
  local signature="$1"
  shift
  [ -n "$signature" ] || return 0

  local cache_dir cache_file tmp_file
  cache_dir="$(_apps_services_cache_dir)"
  cache_file="$(_apps_services_cache_file)"
  tmp_file="${cache_file}.tmp.$$"

  mkdir -p "$cache_dir" 2>/dev/null || return 0
  [ -w "$cache_dir" ] || return 0

  touch "$tmp_file" 2>/dev/null || return 0

  {
    printf 'signature=%s\n' "$signature"
    if [ "$#" -gt 0 ]; then
      printf '%s\n' "$@"
    fi
  } > "$tmp_file" || {
    rm -f "$tmp_file" 2>/dev/null || true
    return 0
  }

  mv -f "$tmp_file" "$cache_file" 2>/dev/null || {
    rm -f "$tmp_file" 2>/dev/null || true
    return 0
  }

  return 0
}

_apps_print_columns() {
  local cols="${1:-3}"
  shift 2>/dev/null || true

  if ! [[ "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -lt 1 ]; then
    cols=3
  fi

  local -a entries=("$@")
  [ ${#entries[@]} -eq 0 ] && return 0

  local max=0 e
  for e in "${entries[@]}"; do
    [ "${#e}" -gt "$max" ] && max="${#e}"
  done
  local width=$((max + 4))

  local i=0
  for e in "${entries[@]}"; do
    printf '%-*s' "$width" "$e"
    i=$((i + 1))
    if [ "$cols" -gt 0 ] && [ $((i % cols)) -eq 0 ]; then
      printf '\n'
    fi
  done
  if [ "$cols" -gt 0 ] && [ $((i % cols)) -ne 0 ]; then
    printf '\n'
  fi
}

_apps_render_menu() {
  local cols="${1:-3}"
  local use_display_name="${2:-1}"
  shift 2 2>/dev/null || true

  if ! [[ "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -lt 1 ]; then
    cols=3
  fi

  local -a services=("$@")
  [ ${#services[@]} -eq 0 ] && return 0

  local num_width="${#services[@]}"
  num_width="${#num_width}"

  local -a entries=()
  local i label
  for i in "${!services[@]}"; do
    if [ "$use_display_name" = "1" ]; then
      label="$(_apps_service_display_name "${services[$i]}")"
    else
      label="${services[$i]}"
    fi
    entries+=("$(printf "%${num_width}d) %s" "$((i+1))" "$label")")
  done

  _apps_print_columns "$cols" "${entries[@]}"
}

_apps_service_is_valid() {
  local service="$1"
  [ -z "$service" ] && return 1

  if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
    appspec_is_valid_v1 "$service" && return 0
  elif declare -F appspec_is_valid_v1_single >/dev/null 2>&1; then
    appspec_is_valid_v1_single "$service" && return 0
  fi

  return 1
}

_apps_service_menu_order() {
  local service="$1"

  local v
  v="$(appspec_get "$service" "menu_order" "")"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$v"
    return 0
  fi

  printf '%s\n' "9999"
}

_apps_service_is_hidden() {
  local service="$1"

  if declare -F appspec_has_service >/dev/null 2>&1 && appspec_has_service "$service"; then
    local v
    v="$(appspec_get "$service" "hidden" "")"
    case "${v,,}" in
      1|true|yes|y) return 0 ;;
    esac
  fi

  return 1
}

_apps_discover_services() {
  local -a services=()

  if declare -F appspec_list_services >/dev/null 2>&1; then
    local s
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      _apps_service_is_valid "$s" || continue
      _apps_service_is_hidden "$s" && continue
      services+=("$s")
    done < <(appspec_list_services)
  fi

  if [ ${#services[@]} -eq 0 ]; then
    return 0
  fi

  printf '%s\n' "${services[@]}" | LC_ALL=C sort -u
}

_apps_list_services() {
  if [ "${TGDB_DISABLE_APPS_SERVICE_CACHE:-0}" = "1" ]; then
    TGDB_APPS_SERVICES_CACHE_VALID=0
    TGDB_APPS_SERVICES_CACHE=()
  fi

  if [ "${TGDB_APPS_SERVICES_CACHE_VALID:-0}" = "1" ]; then
    if [ ${#TGDB_APPS_SERVICES_CACHE[@]} -gt 0 ]; then
      printf '%s\n' "${TGDB_APPS_SERVICES_CACHE[@]}"
    fi
    return 0
  fi

  local cache_signature=""
  if [ "${TGDB_DISABLE_APPS_SERVICE_CACHE:-0}" != "1" ]; then
    cache_signature="$(_apps_services_cache_signature 2>/dev/null || true)"
    if [ -n "$cache_signature" ] && _apps_services_cache_read "$cache_signature"; then
      if [ ${#TGDB_APPS_SERVICES_CACHE[@]} -gt 0 ]; then
        printf '%s\n' "${TGDB_APPS_SERVICES_CACHE[@]}"
      fi
      return 0
    fi
  fi

  local -a discovered=()
  local s
  while IFS= read -r s; do
    [ -n "$s" ] && discovered+=("$s")
  done < <(_apps_discover_services)

  TGDB_APPS_SERVICES_CACHE=()

  if [ ${#discovered[@]} -eq 0 ]; then
    TGDB_APPS_SERVICES_CACHE_VALID=1
    return 0
  fi

  local -a lines=()
  for s in "${discovered[@]}"; do
    local order
    order="$(_apps_service_menu_order "$s")"
    lines+=("$(printf '%04d|%s' "$order" "$s")")
  done

  local -a sorted=()
  mapfile -t sorted < <(printf '%s\n' "${lines[@]}" | LC_ALL=C sort -t'|' -k1,1n -k2,2)
  for s in "${sorted[@]}"; do
    TGDB_APPS_SERVICES_CACHE+=("${s##*|}")
  done

  TGDB_APPS_SERVICES_CACHE_VALID=1
  if [ "${TGDB_DISABLE_APPS_SERVICE_CACHE:-0}" != "1" ] && [ -n "$cache_signature" ]; then
    _apps_services_cache_write "$cache_signature" "${TGDB_APPS_SERVICES_CACHE[@]}" || true
  fi

  if [ ${#TGDB_APPS_SERVICES_CACHE[@]} -gt 0 ]; then
    printf '%s\n' "${TGDB_APPS_SERVICES_CACHE[@]}"
  fi
}

_apps_service_display_name() {
  local service="$1"

  local v
  v="$(appspec_get "$service" "display_name" "")"
  if [ -n "$v" ]; then
    printf '%s\n' "$v"
    return 0
  fi

  printf '%s\n' "$service"
}

_apps_service_doc_url() {
  local service="$1"
  appspec_get "$service" "doc_url" ""
}

_apps_service_uses_volume_dir() {
  local service="$1"
  local v
  v="$(appspec_get "$service" "uses_volume_dir" "0" 2>/dev/null || echo "0")"
  case "${v,,}" in
    1|true|yes|y) return 0 ;;
  esac
  return 1
}

_apps_service_default_image() {
  local service="$1"

  local v
  v="$(appspec_get "$service" "image" "")"
  if [ -n "$v" ]; then
    printf '%s\n' "$v"
    return 0
  fi

  local tpl="$CONFIG_DIR/$service/quadlet/default.container"
  if [ ! -f "$tpl" ]; then
    echo ""
    return 0
  fi

  local line
  line=$(grep -m1 '^Image=' "$tpl" 2>/dev/null || true)
  line="${line#Image=}"
  printf '%s\n' "$line"
}

_apps_unit_container_has_app_label() {
  local mode="$1" unit_path="$2" service="$3"
  [ -n "${mode:-}" ] || return 1
  [ -n "${unit_path:-}" ] || return 1
  [ -n "${service:-}" ] || return 1

  _apps_test "$mode" -r "$unit_path" 2>/dev/null || return 1

  awk -v target="$service" '
    BEGIN { found=0 }
    /^[[:space:]]*Label[[:space:]]*=/ {
      line=$0
      sub(/^[[:space:]]*Label[[:space:]]*=[[:space:]]*/, "", line)
      sub(/[[:space:]]*(#.*)?$/, "", line)
      gsub(/^"|"$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

      n = split(line, parts, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        p = parts[i]
        gsub(/^"|"$/, "", p)
        if (p ~ /^app=/) {
          sub(/^app=/, "", p)
          if (p == target) { found=1; exit }
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' < <(_apps_read_file "$mode" "$unit_path" 2>/dev/null || true)
}

_apps_list_instances_by_label() {
  local service="$1"
  [ -z "$service" ] && return 0
  local mode unit_dir seen=""
  local -a modes=()
  if declare -F _apps_service_supports_deploy_mode >/dev/null 2>&1; then
    _apps_service_supports_deploy_mode "$service" "rootless" && modes+=("rootless")
    _apps_service_supports_deploy_mode "$service" "rootful" && modes+=("rootful")
  fi
  # fallback：避免在意外缺少 helper 時行為改變
  [ ${#modes[@]} -gt 0 ] || modes=(rootless rootful)

  for mode in "${modes[@]}"; do
    unit_dir="$(_apps_unit_dir_for_mode "$mode" 2>/dev/null || echo "")"
    if [ -n "$unit_dir" ] && _apps_dir_exists "$mode" "$unit_dir"; then
      local f=""
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        local base name
        base="${f##*/}"
        case "$base" in
          *.container) name="${base%.container}" ;;
          *) continue ;;
        esac

        # 以 Quadlet unit 內的 Label=app=<service> 判斷歸屬，避免「僅剩紀錄檔」被誤判為已部署。
        if ! _apps_unit_container_has_app_label "$mode" "$f" "$service"; then
          continue
        fi
        if _app_is_aux_instance_name "$service" "$name"; then
          continue
        fi
        case ",$seen," in
          *,"$mode:$name",*) ;;
          *)
            printf '%s\t%s\n' "$name" "$mode"
            seen="$seen,$mode:$name"
            ;;
        esac
      done < <(_apps_find_lines "$mode" "$unit_dir" -maxdepth 1 -type f -name "*.container" 2>/dev/null)
    fi
  done
}

_apps_has_instances_by_label() {
  local service="$1"
  [ -n "${service:-}" ] || return 1

  if _apps_has_podman_instances_by_mode "$service" "rootless"; then
    return 0
  fi
  if _apps_has_podman_instances_by_mode "$service" "rootful"; then
    return 0
  fi

  _apps_list_instances_by_label "$service" 2>/dev/null | head -n 1 | grep -q .
}

_apps_has_podman_instances_by_mode() {
  local service="$1" mode="$2"
  [ -n "$service" ] || return 1
  command -v podman >/dev/null 2>&1 || return 1

  # 若此 service 未宣告支援 rootful，避免為了「顯示」而觸發 sudo 密碼提示。
  if declare -F _apps_service_supports_deploy_mode >/dev/null 2>&1; then
    if ! _apps_service_supports_deploy_mode "$service" "$mode"; then
      return 1
    fi
  fi

  case "$mode" in
    rootful)
      _tgdb_run_privileged podman ps -aq --filter "label=app=${service}" 2>/dev/null | grep -q .
      ;;
    *)
      podman ps -aq --filter "label=app=${service}" 2>/dev/null | grep -q .
      ;;
  esac
}

_apps_print_podman_instances_by_mode() {
  local service="$1" mode="$2"
  [ -n "$service" ] || return 1
  command -v podman >/dev/null 2>&1 || return 1

  if declare -F _apps_service_supports_deploy_mode >/dev/null 2>&1; then
    if ! _apps_service_supports_deploy_mode "$service" "$mode"; then
      return 1
    fi
  fi

  local label
  case "$mode" in
    rootful) label="rootful" ;;
    *) label="rootless" ;;
  esac

  if ! _apps_has_podman_instances_by_mode "$service" "$mode"; then
    return 1
  fi

  echo "--- ${label} ---"
  case "$mode" in
    rootful)
      _tgdb_run_privileged podman ps -a --filter "label=app=${service}" 2>/dev/null || return 1
      ;;
    *)
      podman ps -a --filter "label=app=${service}" 2>/dev/null || return 1
      ;;
  esac
  return 0
}

_apps_print_instances_by_label() {
  local service="$1"
  [ -z "$service" ] && return 0
  local printed=0

  if _apps_print_podman_instances_by_mode "$service" "rootless"; then
    printed=1
  fi

  if _apps_has_podman_instances_by_mode "$service" "rootful"; then
    if [ "$printed" -eq 1 ]; then
      echo
    fi
    if _apps_print_podman_instances_by_mode "$service" "rootful"; then
      printed=1
    fi
  fi

  if [ "$printed" -eq 1 ]; then
    return 0
  fi

  local name mode
  while IFS=$'\t' read -r name mode; do
    [ -n "$name" ] || continue
    printf -- '- %s [%s]\n' "$name" "$mode"
  done < <(_apps_list_instances_by_label "$service")
}
