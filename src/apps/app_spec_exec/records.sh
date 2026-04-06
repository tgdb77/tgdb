#!/bin/bash

# TGDB AppSpec 執行器：紀錄/還原與設定檔複製
# 注意：
# - 本檔案為 library，會被 src/apps/app_spec_exec.sh source
# - 請勿在此更改 shell options（例如 set -euo pipefail）。

appspec_config_label() {
  local service="$1"
  local -a cfg_dests=() cfg_tpls=() cfg_modes=() cfg_labels=()
  _appspec_config_defs "$service" cfg_dests cfg_tpls cfg_modes cfg_labels || { printf '%s\n' ""; return 0; }

  if [ ${#cfg_dests[@]} -eq 0 ]; then
    printf '%s\n' ""
    return 0
  fi

  if [ ${#cfg_dests[@]} -eq 1 ]; then
    local label dest
    label="${cfg_labels[0]:-}"
    dest="${cfg_dests[0]}"
    if [ -n "$label" ]; then
      printf '%s\n' "$label"
    else
      printf '%s\n' "$(basename "$dest" 2>/dev/null || echo "$dest")"
    fi
    return 0
  fi

  local -a parts=()
  local i
  for ((i = 0; i < ${#cfg_dests[@]}; i++)); do
    local label dest p
    label="${cfg_labels[$i]:-}"
    dest="${cfg_dests[$i]}"
    if [ -n "$label" ]; then
      p="$label"
    else
      p="$(basename "$dest" 2>/dev/null || echo "$dest")"
    fi
    parts+=("$p")
    [ ${#parts[@]} -ge 3 ] && break
  done

  local joined=""
  for i in "${!parts[@]}"; do
    joined+="${joined:+、}${parts[$i]}"
  done
  if [ ${#cfg_dests[@]} -gt 3 ]; then
    joined+="…"
  fi
  printf '%s\n' "設定檔（$joined）"
}

_appspec_config_record_ext() {
  local dest_basename="$1"
  local ext="${dest_basename##*.}"
  if [ -z "$ext" ] || [ "$ext" = "$dest_basename" ]; then
    ext="conf"
  fi
  case "$ext" in
    json|toml|conf|env) ;;
    *)
      ext="conf"
      ;;
  esac
  printf '%s\n' "$ext"
}

appspec_record_config_path() {
  local service="$1" name="$2"
  local -a cfg_dests=() cfg_tpls=() cfg_modes=() cfg_labels=()
  _appspec_config_defs "$service" cfg_dests cfg_tpls cfg_modes cfg_labels || { printf '%s\n' ""; return 0; }
  if [ ${#cfg_dests[@]} -eq 0 ]; then
    printf '%s\n' ""
    return 0
  fi

  if [ ${#cfg_dests[@]} -gt 1 ]; then
    local dir dest base
    dir="$(rm_service_configs_dir "$service")"
    dest="${cfg_dests[0]}"
    base="$(basename "$dest" 2>/dev/null || echo "$dest")"
    printf '%s\n' "$dir/${name}__${base}"
    return 0
  fi

  local dest base ext
  dest="${cfg_dests[0]}"
  base="$(basename "$dest" 2>/dev/null || echo "$dest")"
  ext="$(_appspec_config_record_ext "$base")"
  printf '%s\n' "$(rm_service_configs_dir "$service")/$name.$ext"
}

appspec_record_config_paths() {
  local service="$1" name="$2"

  local -a cfg_dests=() cfg_tpls=() cfg_modes=() cfg_labels=()
  _appspec_config_defs "$service" cfg_dests cfg_tpls cfg_modes cfg_labels || return 1
  if [ ${#cfg_dests[@]} -eq 0 ]; then
    return 0
  fi

  if [ ${#cfg_dests[@]} -gt 1 ]; then
    local dir
    dir="$(rm_service_configs_dir "$service")"
    local i
    for ((i = 0; i < ${#cfg_dests[@]}; i++)); do
      local dest base
      dest="${cfg_dests[$i]}"
      base="$(basename "$dest" 2>/dev/null || echo "$dest")"
      printf '%s\n' "$dir/${name}__${base}"
    done
    return 0
  fi

  local i
  for ((i = 0; i < ${#cfg_dests[@]}; i++)); do
    local dest base ext
    dest="${cfg_dests[$i]}"
    base="$(basename "$dest" 2>/dev/null || echo "$dest")"
    ext="$(_appspec_config_record_ext "$base")"
    printf '%s\n' "$(rm_service_configs_dir "$service")/$name.$ext"
  done
}

appspec_copy_config_to_instance() {
  local service="$1" config_path="$2" instance_dir="$3"
  local deploy_mode
  deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"

  local -a cfg_dests=() cfg_tpls=() cfg_modes=() cfg_labels=()
  _appspec_config_defs "$service" cfg_dests cfg_tpls cfg_modes cfg_labels || return 1
  [ ${#cfg_dests[@]} -gt 0 ] || return 0

  local dest_rel tpl_rel mode
  if [ ${#cfg_dests[@]} -eq 1 ]; then
    dest_rel="${cfg_dests[0]}"
    tpl_rel="${cfg_tpls[0]}"
    mode="${cfg_modes[0]:-}"
  else
    # 多設定檔：優先用 record 檔名對應 dest basename（避免同副檔名衝突）。
    # - record 檔名：${name}__${dest_basename}（由 appspec_record_config_paths 產生）
    local base i
    base="$(basename "$config_path" 2>/dev/null || echo "$config_path")"
    local rec_name="${base%%__*}"
    local rec_tail=""
    if [[ "$base" == *__* ]] && [ -n "$rec_name" ]; then
      rec_tail="${base#*__}"
    fi

    local found=0
    if [ -n "$rec_tail" ]; then
      for ((i = 0; i < ${#cfg_dests[@]}; i++)); do
        local dest_base
        dest_base="$(basename "${cfg_dests[$i]}" 2>/dev/null || echo "${cfg_dests[$i]}")"
        if [ "$dest_base" = "$rec_tail" ]; then
          dest_rel="${cfg_dests[$i]}"
          tpl_rel="${cfg_tpls[$i]}"
          mode="${cfg_modes[$i]:-}"
          found=1
          break
        fi
      done
    fi

    if [ "$found" -ne 1 ]; then
      tgdb_warn "無法判斷設定檔目標（$service）：$config_path（已略過）"
      return 0
    fi
  fi

  if ! _appspec_instance_rel_path_is_safe "$dest_rel"; then
    tgdb_warn "AppSpec config_dest 不合法（$service）：$dest_rel（已略過複製）"
    return 0
  fi

  local dest="$instance_dir/$dest_rel"
  _apps_mkdir_p "$deploy_mode" "$(dirname "$dest")" || return 1

  if [ -n "$config_path" ] && _apps_test "$deploy_mode" -f "$config_path"; then
    if [ "$config_path" != "$dest" ]; then
      _apps_copy_file_to_mode "$deploy_mode" "$config_path" "$dest" 2>/dev/null || true
    fi
  else
    if [ -n "$tpl_rel" ]; then
      local tpl
      tpl="$(_appspec_join_service_path "$service" "$tpl_rel")" || return 0
      if [ -f "$tpl" ] && ! _apps_path_exists "$deploy_mode" "$dest"; then
        _apps_copy_file_to_mode "$deploy_mode" "$tpl" "$dest" 2>/dev/null || true
      fi
    fi
  fi

  if [ -n "$mode" ] && [[ "$mode" =~ ^[0-9]+$ ]]; then
    if [ "$deploy_mode" = "rootful" ]; then
      _tgdb_run_privileged chmod "$mode" "$dest" 2>/dev/null || true
    else
      chmod "$mode" "$dest" 2>/dev/null || true
    fi
  fi

  # 一些服務需要先建立特定檔案，避免容器啟動時被建立成同名資料夾（例如：Volume 掛載檔案時）。
  _appspec_touch_files "$service" "$instance_dir" "touch_files" || return 1
}

appspec_record_files() {
  local service="$1" name="$2"
  local deploy_mode
  deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"

  local qdir
  qdir="$(rm_service_quadlet_dir "$service" 2>/dev/null || echo "")"

  local quadlet_type
  quadlet_type="$(appspec_get "$service" "quadlet_type" "")"
  if [ "$quadlet_type" = "multi" ]; then
    local -a unit_suffixes=() unit_tpls=() unit_kvs=()
    if _appspec_unit_defs "$service" unit_suffixes unit_tpls unit_kvs; then
      local i
      for ((i = 0; i < ${#unit_suffixes[@]}; i++)); do
        local f="$qdir/${name}${unit_suffixes[$i]}"
        _apps_path_exists "$deploy_mode" "$f" && printf '%s\n' "$f"
      done
    fi
  else
    local quad
    quad="$qdir/$name.container"
    _apps_path_exists "$deploy_mode" "$quad" && printf '%s\n' "$quad"
  fi

  local -a cfgs=()
  if appspec_can_handle "$service" record_config_paths; then
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && cfgs+=("$line")
    done < <(appspec_record_config_paths "$service" "$name" 2>/dev/null || true)
  else
    local cfg
    cfg="$(appspec_record_config_path "$service" "$name" 2>/dev/null || echo "")"
    [ -n "$cfg" ] && cfgs+=("$cfg")
  fi

  local c
  for c in "${cfgs[@]}"; do
    [ -n "$c" ] && _apps_path_exists "$deploy_mode" "$c" && printf '%s\n' "$c"
  done
}

appspec_deploy_from_record() {
  local service="$1" name="$2"

  _appspec_maybe_enable_podman_socket "$service" || true

  local quadlet_type
  quadlet_type="$(appspec_get "$service" "quadlet_type" "")"

  local subdirs_raw
  subdirs_raw="$(appspec_get "$service" "record_subdirs" "")"
  if [ -z "$subdirs_raw" ]; then
    subdirs_raw="$(appspec_get "$service" "instance_subdirs" "")"
  fi

  if [ "$quadlet_type" = "multi" ]; then
    # shellcheck disable=SC2034 # unit_tpls/unit_kvs 僅用於 _appspec_unit_defs 回傳（此處不需要）
    local -a unit_suffixes=() unit_tpls=() unit_kvs=()
    _appspec_unit_defs "$service" unit_suffixes unit_tpls unit_kvs || {
      tgdb_fail "AppSpec multi 缺少 unit 定義（$service）。" 1 || true
      return 1
    }

    local -a units=()
    local i
    for ((i = 0; i < ${#unit_suffixes[@]}; i++)); do
      units+=("${name}${unit_suffixes[$i]}")
    done

    if [ -n "$subdirs_raw" ]; then
      local -a subdirs=()
      _appspec_parse_subdirs subdirs "$subdirs_raw" "record_subdirs" || return 1
      _app_deploy_from_record_multi "$service" "$name" "${units[@]}" --mkdir "${subdirs[@]}"
    else
      _app_deploy_from_record_multi "$service" "$name" "${units[@]}"
    fi
    return $?
  fi

  if [ -n "$subdirs_raw" ]; then
    local -a subdirs=()
    _appspec_parse_subdirs subdirs "$subdirs_raw" "record_subdirs" || return 1
    _app_deploy_from_record_single "$service" "$name" "${subdirs[@]}"
  else
    _app_deploy_from_record_single "$service" "$name"
  fi
}
