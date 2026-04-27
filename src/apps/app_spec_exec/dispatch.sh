#!/bin/bash

# TGDB AppSpec 執行器：動作判斷/分派
# 注意：
# - 本檔案為 library，會被 src/apps/app_spec_exec.sh source
# - 請勿在此更改 shell options（例如 set -euo pipefail）。

_appspec_service_is_valid() {
  local service="$1"
  if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
    appspec_is_valid_v1 "$service"
    return $?
  fi
  appspec_is_valid_v1_single "$service"
}

_appspec_has_config() {
  local service="$1"
  local config_raw=""
  config_raw="$(appspec_get_all "$service" "config" 2>/dev/null || true)"
  [ -n "$config_raw" ] || [ -n "$(appspec_get "$service" "config_dest" "")" ]
}

_appspec_has_success_messages() {
  local service="$1"
  local raw_extra raw_warn
  raw_extra="$(appspec_get_all "$service" "success_extra" 2>/dev/null || true)"
  raw_warn="$(appspec_get_all "$service" "success_warn" 2>/dev/null || true)"
  [ -n "$raw_extra" ] || [ -n "$raw_warn" ]
}

_appspec_has_hook_scripts() {
  local service="$1" hook_key="$2"
  [ -n "$(appspec_get_all "$service" "$hook_key" 2>/dev/null || true)" ]
}

_appspec_has_pre_build_hooks() {
  _appspec_has_hook_scripts "$1" "pre_build"
}

_appspec_has_post_build_hooks() {
  _appspec_has_hook_scripts "$1" "post_build"
}

_appspec_has_post_deploy_hooks() {
  local service="$1"
  _appspec_has_hook_scripts "$service" "post_deploy"
}

_appspec_has_mount_options() {
  local service="$1"
  [ -n "$(appspec_get "$service" "mount_propagation" "")" ]
}

_appspec_uses_volume_dir() {
  local service="$1"
  local v
  v="$(appspec_get "$service" "uses_volume_dir" "0")"
  _appspec_truthy "$v"
}

_appspec_has_cli_quick() {
  local service="$1"
  local args_raw
  args_raw="$(appspec_get "$service" "cli_quick_args" "")"
  [ -n "$args_raw" ]
}

appspec_can_handle() {
  local service="$1" action="$2"
  appspec_has_service "$service" || return 1

  case "$action" in
    is_aux_instance_name)
      local quadlet_type
      quadlet_type="$(appspec_get "$service" "quadlet_type" "")"
      [ "$quadlet_type" = "multi" ] || return 1
      return 0
      ;;
    print_deploy_success)
      _appspec_service_is_valid "$service" || return 1
      _appspec_has_success_messages "$service"
      return $?
      ;;
    post_deploy)
      _appspec_service_is_valid "$service" || return 1
      _appspec_has_post_deploy_hooks "$service"
      return $?
      ;;
    pre_build)
      _appspec_service_is_valid "$service" || return 1
      _appspec_has_pre_build_hooks "$service"
      return $?
      ;;
    post_build)
      _appspec_service_is_valid "$service" || return 1
      _appspec_has_post_build_hooks "$service"
      return $?
      ;;
    update_and_restart_instance|full_remove_instance)
      _appspec_service_is_valid "$service" || return 1
      return 0
      ;;
    default_base_port|prepare_instance|render_quadlet|deploy_from_record|record_files)
      _appspec_service_is_valid "$service" || return 1
      return 0
      ;;
    ask_mount_options)
      _appspec_service_is_valid "$service" || return 1
      _appspec_has_mount_options "$service" || return 1
      return 0
      ;;
    ask_volume_dir)
      _appspec_service_is_valid "$service" || return 1
      _appspec_uses_volume_dir "$service"
      return $?
      ;;
    cli_quick_min_args|cli_quick|cli_quick_usage)
      _appspec_service_is_valid "$service" || return 1
      _appspec_has_cli_quick "$service"
      return $?
      ;;
    config_label)
      _appspec_service_is_valid "$service" || return 1
      _appspec_has_config "$service"
      return $?
      ;;
    record_config_path|record_config_paths|copy_config_to_instance)
      _appspec_service_is_valid "$service" || return 1
      _appspec_has_config "$service"
      return $?
      ;;
    *)
      return 1
      ;;
  esac
}

appspec_invoke() {
  local service="$1" action="$2"
  shift 2 || true

  case "$action" in
    is_aux_instance_name) appspec_is_aux_instance_name "$service" "$@" ;;
    print_deploy_success) appspec_print_deploy_success "$service" "$@" ;;
    pre_build) appspec_pre_build "$service" "$@" ;;
    post_build) appspec_post_build "$service" "$@" ;;
    post_deploy) appspec_post_deploy "$service" "$@" ;;
    update_and_restart_instance) appspec_update_and_restart_instance "$service" "$@" ;;
    full_remove_instance) appspec_full_remove_instance "$service" "$@" ;;
    default_base_port) appspec_default_base_port "$service" ;;
    prepare_instance) appspec_prepare_instance "$service" "$@" ;;
    render_quadlet) appspec_render_quadlet "$service" "$@" ;;
    deploy_from_record) appspec_deploy_from_record "$service" "$@" ;;
    record_files) appspec_record_files "$service" "$@" ;;
    ask_mount_options) appspec_ask_mount_options "$service" "$@" ;;
    ask_volume_dir) appspec_ask_volume_dir "$service" "$@" ;;
    cli_quick_min_args) appspec_cli_quick_min_args "$service" ;;
    cli_quick_usage) appspec_cli_quick_usage "$service" ;;
    cli_quick) appspec_cli_quick "$service" "$@" ;;
    config_label) appspec_config_label "$service" ;;
    record_config_path) appspec_record_config_path "$service" "$@" ;;
    record_config_paths) appspec_record_config_paths "$service" "$@" ;;
    copy_config_to_instance) appspec_copy_config_to_instance "$service" "$@" ;;
    *)
      tgdb_fail "服務 '$service' 尚未支援動作 '$action'（AppSpec）" 1 || return $?
      return 1
      ;;
  esac
}
