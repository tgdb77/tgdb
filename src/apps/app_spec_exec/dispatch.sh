#!/bin/bash

# TGDB AppSpec 執行器：動作判斷/分派
# 注意：
# - 本檔案為 library，會被 src/apps/app_spec_exec.sh source
# - 請勿在此更改 shell options（例如 set -euo pipefail）。

appspec_can_handle() {
  local service="$1" action="$2"
  appspec_has_service "$service" || return 1

  local has_config=0
  local config_raw=""
  config_raw="$(appspec_get_all "$service" "config" 2>/dev/null || true)"
  if [ -n "$config_raw" ] || [ -n "$(appspec_get "$service" "config_dest" "")" ]; then
    has_config=1
  fi

  case "$action" in
    is_aux_instance_name)
      local quadlet_type
      quadlet_type="$(appspec_get "$service" "quadlet_type" "")"
      [ "$quadlet_type" = "multi" ] || return 1
      return 0
      ;;
    print_deploy_success)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      local raw_extra raw_warn
      raw_extra="$(appspec_get_all "$service" "success_extra" 2>/dev/null || true)"
      raw_warn="$(appspec_get_all "$service" "success_warn" 2>/dev/null || true)"
      [ -n "$raw_extra" ] || [ -n "$raw_warn" ]
      return $?
      ;;
    post_deploy)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      [ -n "$(appspec_get_all "$service" "post_deploy" 2>/dev/null || true)" ]
      return $?
      ;;
    update_and_restart_instance|full_remove_instance)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      return 0
      ;;
    default_base_port|prepare_instance|render_quadlet|deploy_from_record|record_files)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      return 0
      ;;
    ask_mount_options)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      [ -n "$(appspec_get "$service" "mount_propagation" "")" ] || return 1
      return 0
      ;;
    ask_volume_dir)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      local v
      v="$(appspec_get "$service" "uses_volume_dir" "0")"
      _appspec_truthy "$v"
      return $?
      ;;
    cli_quick_min_args|cli_quick|cli_quick_usage)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      local args_raw
      args_raw="$(appspec_get "$service" "cli_quick_args" "")"
      [ -n "$args_raw" ]
      return $?
      ;;
    config_label)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      [ "$has_config" -eq 1 ]
      return $?
      ;;
    record_config_path|record_config_paths|copy_config_to_instance)
      if declare -F appspec_is_valid_v1 >/dev/null 2>&1; then
        appspec_is_valid_v1 "$service" || return 1
      else
        appspec_is_valid_v1_single "$service" || return 1
      fi
      [ "$has_config" -eq 1 ]
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
