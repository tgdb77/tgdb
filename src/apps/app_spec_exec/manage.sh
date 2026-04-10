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

appspec_post_deploy() {
  local service="$1" name="$2"

  local instance_dir
  instance_dir="${TGDB_DIR:?}/$name"

  local host_port
  host_port="$(_appspec_ctx_get "$service" "$name" "host_port" "")"
  _appspec_run_hook_scripts "$service" "$name" "$instance_dir" "$host_port" "post_deploy"
}

appspec_update_and_restart_instance() {
  local service="$1" name="$2" main_image="${3:-}"

  _appspec_maybe_enable_podman_socket "$service" || true

  if [ -n "${main_image:-}" ] && command -v podman >/dev/null 2>&1; then
    tgdb_podman pull "$main_image" || true

    local raw img
    raw="$(appspec_get_all "$service" "update_pull_images" 2>/dev/null || true)"
    if [ -n "$raw" ]; then
      while IFS= read -r img; do
        [ -n "$img" ] || continue
        tgdb_podman pull "$img" || true
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
    tgdb_systemctl_try "$(_apps_current_scope 2>/dev/null || printf '%s\n' "user")" restart -- "${name}.container" "${name}.service" "container-${name}.service" || true
  fi
}

appspec_full_remove_instance() {
  local service="$1" name="$2" deld="${3:-n}" delv="${4:-n}"
  local deploy_mode unit_dir

  _appspec_maybe_enable_podman_socket "$service" || true
  deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"
  unit_dir="$(_apps_unit_dir_for_mode "$deploy_mode" 2>/dev/null || rm_user_units_dir)"

  local -a units=()
  local u
  while IFS= read -r u; do
    [ -n "$u" ] && units+=("$u")
  done < <(_appspec_units_for_instance "$service" "$name" 2>/dev/null || true)

  if [ ${#units[@]} -gt 0 ] && declare -F _app_full_remove_units_by_filenames >/dev/null 2>&1; then
    _app_full_remove_units_by_filenames "${units[@]}"
  else
    tgdb_systemctl_try "$(_apps_current_scope 2>/dev/null || printf '%s\n' "user")" disable --now -- "${name}.container" "${name}.service" "container-${name}.service" || true
    tgdb_podman rm -f "$name" 2>/dev/null || true
    _apps_remove_file "$deploy_mode" "$unit_dir/${name}.container" 2>/dev/null || true
  fi

  if [[ "${deld:-n}" =~ ^[Yy]$ ]]; then
    local delete_path method
    delete_path="${TGDB_DIR:?}/$name"
    method="$(appspec_get "$service" "full_remove_delete_method" "auto")"
    if declare -F _app_try_delete_path >/dev/null 2>&1; then
      _app_try_delete_path "$delete_path" "$method" || true
    else
      if [ "$deploy_mode" = "rootful" ]; then
        _tgdb_run_privileged rm -rf "$delete_path" 2>/dev/null || true
      else
        tgdb_podman unshare rm -rf "$delete_path" 2>/dev/null || true
      fi
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
    method="$(appspec_get "$service" "full_remove_delete_method" "auto")"
    if declare -F _app_try_delete_path >/dev/null 2>&1; then
      _app_try_delete_path "$volume_dir" "$method" || true
    else
      if [ "$deploy_mode" = "rootful" ]; then
        _tgdb_run_privileged rm -rf "$volume_dir" 2>/dev/null || true
      else
        tgdb_podman unshare rm -rf "$volume_dir" 2>/dev/null || true
      fi
    fi
  fi

  local purge
  purge="$(appspec_get "$service" "full_remove_purge_record" "0")"
  if _appspec_truthy "$purge"; then
    local f
    while IFS= read -r f; do
      if [ -n "$f" ]; then
        _apps_remove_file "$deploy_mode" "$f" 2>/dev/null || true
      fi
    done < <(appspec_record_files "$service" "$name" 2>/dev/null || true)
  fi

  echo "✅ 已嘗試清理完成：$name"
}
