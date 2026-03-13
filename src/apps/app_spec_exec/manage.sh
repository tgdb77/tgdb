#!/bin/bash

# TGDB AppSpec 執行器：更新/移除/成功提示（非骨架）
# 注意：
# - 本檔案為 library，會被 src/apps/app_spec_exec.sh source
# - 請勿在此更改 shell options（例如 set -euo pipefail）。

_appspec_units_for_instance() {
  local service="$1" name="$2"

  local quadlet_type
  quadlet_type="$(appspec_get "$service" "quadlet_type" "")"
  if [ "$quadlet_type" != "multi" ]; then
    printf '%s\n' "${name}.container"
    return 0
  fi

  # shellcheck disable=SC2034 # unit_tpls/unit_kvs 僅用於 _appspec_unit_defs 回傳（此處不需要）
  local -a unit_suffixes=() unit_tpls=() unit_kvs=()
  _appspec_unit_defs "$service" unit_suffixes unit_tpls unit_kvs || return 1

  local -a containers=() pods=() others=()
  local i suffix unit
  for ((i = 0; i < ${#unit_suffixes[@]}; i++)); do
    suffix="${unit_suffixes[$i]}"
    unit="${name}${suffix}"
    case "$suffix" in
      *.container) containers+=("$unit") ;;
      *.pod) pods+=("$unit") ;;
      *) others+=("$unit") ;;
    esac
  done

  local u
  for u in "${containers[@]}"; do printf '%s\n' "$u"; done
  for u in "${pods[@]}"; do printf '%s\n' "$u"; done
  for u in "${others[@]}"; do printf '%s\n' "$u"; done
  return 0
}

appspec_is_aux_instance_name() {
  local service="$1" name="$2"

  local quadlet_type
  quadlet_type="$(appspec_get "$service" "quadlet_type" "")"
  [ "$quadlet_type" = "multi" ] || return 1

  # shellcheck disable=SC2034 # unit_tpls/unit_kvs 僅用於 _appspec_unit_defs 回傳（此處不需要）
  local -a unit_suffixes=() unit_tpls=() unit_kvs=()
  _appspec_unit_defs "$service" unit_suffixes unit_tpls unit_kvs || return 1

  local i suffix token
  for ((i = 0; i < ${#unit_suffixes[@]}; i++)); do
    suffix="${unit_suffixes[$i]}"
    case "$suffix" in
      -*.container)
        token="${suffix#-}"
        token="${token%.container}"
        ;;
      -*.pod)
        token="${suffix#-}"
        token="${token%.pod}"
        ;;
      *)
        continue
        ;;
    esac
    [ -n "$token" ] || continue
    case "$name" in
      *-"$token") return 0 ;;
    esac
  done

  return 1
}

appspec_print_deploy_success() {
  local service="$1" name="$2" host_port="$3" instance_dir="$4"

  local raw_extra raw_warn
  raw_extra="$(appspec_get_all "$service" "success_extra" 2>/dev/null || true)"
  raw_warn="$(appspec_get_all "$service" "success_warn" 2>/dev/null || true)"
  [ -n "$raw_extra" ] || [ -n "$raw_warn" ] || return 0

  local display_name
  display_name="$(appspec_get "$service" "display_name" "$service")"

  local access_host access_port publish_scope access_url http_url https_url
  access_host="${TGDB_APP_ACCESS_HOST:-}"
  access_port="${TGDB_APP_ACCESS_PORT:-$host_port}"
  publish_scope="${TGDB_APP_PUBLISH_SCOPE:-}"
  access_url=""
  http_url=""
  https_url=""
  if [ -n "$access_host" ] && [ -n "$access_port" ]; then
    access_url="${access_host}:${access_port}"
    http_url="http://${access_host}:${access_port}"
    https_url="https://${access_host}:${access_port}"
  fi

  local user_name pass_word volume_dir
  user_name="$(_appspec_ctx_get "$service" "$name" "user_name" "")"
  pass_word="$(_appspec_ctx_get "$service" "$name" "pass_word" "")"
  volume_dir="$(_appspec_ctx_get "$service" "$name" "volume_dir" "")"

  local -a kv_args=()
  _appspec_build_render_kv_args kv_args "$service" "$name"
  kv_args+=(
    "service=$service"
    "display_name=$display_name"
    "publish_scope=$publish_scope"
    "access_host=$access_host"
    "access_port=$access_port"
    "access_url=$access_url"
    "http_url=$http_url"
    "https_url=$https_url"
  )

  local tmp
  tmp="$(mktemp 2>/dev/null || mktemp -t tgdb_appspec_success)" || {
    tgdb_warn "無法建立暫存檔，將略過 success_extra（$service）。"
    return 0
  }

  local line rendered
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s' "$line" >"$tmp"
    rendered="$(_render_quadlet_template "$tmp" "$name" "$host_port" "$instance_dir" "$volume_dir" "$user_name" "$pass_word" "${kv_args[@]}")"
    [ -n "$rendered" ] && printf '%s\n' "$rendered"
  done <<< "$raw_extra"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s' "$line" >"$tmp"
    rendered="$(_render_quadlet_template "$tmp" "$name" "$host_port" "$instance_dir" "$volume_dir" "$user_name" "$pass_word" "${kv_args[@]}")"
    [ -n "$rendered" ] && tgdb_warn "$rendered"
  done <<< "$raw_warn"

  rm -f "$tmp" 2>/dev/null || true
  return 0
}

_appspec_post_deploy_export_env() {
  local service="$1" name="$2"

  _appspec_export_env "TGDB_SERVICE" "$service" || true
  _appspec_export_env "TGDB_APP_NAME" "$name" || true

  # 匯出 ctx 內的所有變數（包含 input/var 與保留鍵）
  local prefix="${service}:${name}:"
  local full key value
  for full in "${!TGDB_APPSPEC_CTX[@]}"; do
    case "$full" in
      "${prefix}"*)
        key="${full#"$prefix"}"
        value="${TGDB_APPSPEC_CTX[$full]}"
        if declare -F _env_key_is_valid >/dev/null 2>&1; then
          _env_key_is_valid "$key" || continue
        else
          [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        fi
        _appspec_export_env "$key" "$value" || true
        ;;
    esac
  done

  # 另外把 input=/var= 宣告的 env= 鍵也補齊（方便腳本使用大寫 ENV_KEY，不必解析 .env）
  local line def_key env_key
  local -A opts=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opts=()
    _appspec_parse_pipe_def "$line" def_key opts || true
    [ -n "$def_key" ] || continue
    env_key="${opts[env]:-}"
    [ -n "$env_key" ] || continue
    value="$(_appspec_ctx_get "$service" "$name" "$def_key" "")"
    [ -n "$value" ] || continue
    _appspec_export_env "$env_key" "$value" || true
  done < <(appspec_get_all "$service" "input" 2>/dev/null || true)

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opts=()
    _appspec_parse_pipe_def "$line" def_key opts || true
    [ -n "$def_key" ] || continue
    env_key="${opts[env]:-}"
    [ -n "$env_key" ] || continue
    value="$(_appspec_ctx_get "$service" "$name" "$def_key" "")"
    [ -n "$value" ] || continue
    _appspec_export_env "$env_key" "$value" || true
  done < <(appspec_get_all "$service" "var" 2>/dev/null || true)
}

appspec_post_deploy() {
  local service="$1" name="$2"

  local raw
  raw="$(appspec_get_all "$service" "post_deploy" 2>/dev/null || true)"
  [ -n "$raw" ] || return 0

  local instance_dir
  instance_dir="${TGDB_DIR:?}/$name"

  local host_port
  host_port="$(_appspec_ctx_get "$service" "$name" "host_port" "")"

  local line script_rel
  while IFS= read -r line; do
    [ -n "$line" ] || continue

    local -A opts=()
    _appspec_parse_pipe_def "$line" script_rel opts || true
    [ -n "$script_rel" ] || continue

    local allow_fail runner
    allow_fail="${opts[allow_fail]:-0}"
    runner="${opts[runner]:-bash}"

    local script
    script="$(_appspec_join_service_path "$service" "$script_rel")" || return 1
    if [ ! -f "$script" ]; then
      if _appspec_truthy "$allow_fail"; then
        tgdb_warn "找不到 post_deploy 腳本，已略過（$service）：$script_rel"
        continue
      fi
      tgdb_fail "找不到 post_deploy 腳本（$service）：$script_rel" 1 || true
      return 1
    fi

    local rc=0
    case "$runner" in
      source)
        (
          _appspec_post_deploy_export_env "$service" "$name"
          set -- "$service" "$name" "$instance_dir" "$host_port"
          # shellcheck disable=SC1090 # 腳本由 app.spec 指定，於執行期載入
          source "$script"
        ) || rc=$?
        ;;
      bash|"")
        (
          _appspec_post_deploy_export_env "$service" "$name"
          bash "$script" "$service" "$name" "$instance_dir" "$host_port"
        ) || rc=$?
        ;;
      *)
        tgdb_warn "不支援的 post_deploy runner（$service）：$runner，將改用 bash"
        (
          _appspec_post_deploy_export_env "$service" "$name"
          bash "$script" "$service" "$name" "$instance_dir" "$host_port"
        ) || rc=$?
        ;;
    esac

    if [ "$rc" -ne 0 ]; then
      if _appspec_truthy "$allow_fail"; then
        tgdb_warn "post_deploy 執行失敗但已忽略（$service/$name）：$script_rel（rc=$rc）"
        continue
      fi
      tgdb_fail "post_deploy 執行失敗（$service/$name）：$script_rel（rc=$rc）" 1 || true
      return 1
    fi
  done <<< "$raw"

  return 0
}

appspec_update_and_restart_instance() {
  local service="$1" name="$2" main_image="${3:-}"

  _appspec_maybe_enable_podman_socket "$service" || true

  if [ -n "${main_image:-}" ] && command -v podman >/dev/null 2>&1; then
    podman pull "$main_image" || true

    local raw img
    raw="$(appspec_get_all "$service" "update_pull_images" 2>/dev/null || true)"
    if [ -n "$raw" ]; then
      while IFS= read -r img; do
        [ -n "$img" ] || continue
        podman pull "$img" || true
      done <<< "$raw"
    fi
  fi

  local -a units=()
  local u
  while IFS= read -r u; do
    [ -n "$u" ] && units+=("$u")
  done < <(_appspec_units_for_instance "$service" "$name" 2>/dev/null || true)

  if [ ${#units[@]} -gt 0 ] && declare -F _app_restart_units_by_filenames >/dev/null 2>&1; then
    _app_restart_units_by_filenames "${units[@]}"
  else
    _systemctl_user_try restart -- "${name}.container" "${name}.service" "container-${name}.service" || true
  fi
}

appspec_full_remove_instance() {
  local service="$1" name="$2" deld="${3:-n}" delv="${4:-n}"

  _appspec_maybe_enable_podman_socket "$service" || true

  local -a units=()
  local u
  while IFS= read -r u; do
    [ -n "$u" ] && units+=("$u")
  done < <(_appspec_units_for_instance "$service" "$name" 2>/dev/null || true)

  if [ ${#units[@]} -gt 0 ] && declare -F _app_full_remove_units_by_filenames >/dev/null 2>&1; then
    _app_full_remove_units_by_filenames "${units[@]}"
  else
    _systemctl_user_try disable --now -- "${name}.container" "${name}.service" "container-${name}.service" || true
    podman rm -f "$name" 2>/dev/null || true
    rm -f "$(rm_user_units_dir)/${name}.container" 2>/dev/null || true
  fi

  if [[ "${deld:-n}" =~ ^[Yy]$ ]]; then
    local delete_path method
    delete_path="${TGDB_DIR:?}/$name"
    method="$(appspec_get "$service" "full_remove_delete_method" "unshare")"
    if declare -F _app_try_delete_path >/dev/null 2>&1; then
      _app_try_delete_path "$delete_path" "$method" || true
    else
      podman unshare rm -rf "$delete_path" 2>/dev/null || true
    fi
  fi

  if [[ "${delv:-n}" =~ ^[Yy]$ ]]; then
    local uses_volume
    uses_volume="$(appspec_get "$service" "uses_volume_dir" "0")"
    if ! _appspec_truthy "$uses_volume"; then
      delv="n"
    fi
  fi

  if [[ "${delv:-n}" =~ ^[Yy]$ ]]; then
    local backup_root volume_dir method
    if declare -F tgdb_backup_root >/dev/null 2>&1; then
      backup_root="$(tgdb_backup_root)"
    else
      backup_root="${TGDB_BACKUP_ROOT:-$(dirname "${TGDB_DIR:-$HOME/.tgdb/app}")}"
    fi
    volume_dir="$backup_root/volume/$service/$name"
    method="$(appspec_get "$service" "full_remove_delete_method" "unshare")"
    if declare -F _app_try_delete_path >/dev/null 2>&1; then
      _app_try_delete_path "$volume_dir" "$method" || true
    else
      podman unshare rm -rf "$volume_dir" 2>/dev/null || true
    fi
  fi

  local purge
  purge="$(appspec_get "$service" "full_remove_purge_record" "0")"
  if _appspec_truthy "$purge"; then
    local f
    while IFS= read -r f; do
      [ -n "$f" ] && rm -f "$f" 2>/dev/null || true
    done < <(appspec_record_files "$service" "$name" 2>/dev/null || true)
  fi

  echo "✅ 已嘗試清理完成：$name"
}
