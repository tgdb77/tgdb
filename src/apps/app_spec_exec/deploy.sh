#!/bin/bash

# TGDB AppSpec 執行器：部署（prepare/render/ask）
# 注意：
# - 本檔案為 library，會被 src/apps/app_spec_exec.sh source
# - 請勿在此更改 shell options（例如 set -euo pipefail）。

appspec_default_base_port() {
  local service="$1"
  local v
  v="$(appspec_get "$service" "base_port" "0")"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$v"
  else
    tgdb_warn "AppSpec base_port 無效（$service）：$v，已改用 0"
    printf '%s\n' "0"
  fi
}

_appspec_write_staging_unit_file() {
  local path="$1" content="$2"
  local dir
  dir="$(dirname "$path")"

  if ! mkdir -p "$dir" 2>/dev/null; then
    tgdb_fail "無法建立暫存單元目錄：$dir" 1 || true
    return 1
  fi

  if ! printf '%s' "$content" >"$path"; then
    tgdb_fail "無法寫入暫存單元檔：$path" 1 || true
    return 1
  fi
}

_appspec_parse_subdirs() {
  # shellcheck disable=SC2178 # out_ref 透過 nameref 回傳（shellcheck 誤判）
  local -n out_ref="$1"
  local raw="$2" label="$3"

  out_ref=()

  local seg
  for seg in $raw; do
    [ -z "$seg" ] && continue
    if ! _appspec_instance_rel_path_is_safe "$seg"; then
      tgdb_fail "AppSpec ${label} 不合法：$seg" 1 || true
      return 1
    fi
    out_ref+=("$seg")
  done

  return 0
}

_appspec_touch_files() {
  local service="$1" instance_dir="$2" label="$3"

  local raw
  raw="$(appspec_get "$service" "$label" "")"
  [ -n "$raw" ] || return 0

  local seg
  for seg in $raw; do
    [ -z "$seg" ] && continue
    if ! _appspec_instance_rel_path_is_safe "$seg"; then
      tgdb_fail "AppSpec ${label} 不合法：$seg（$service）" 1 || true
      return 1
    fi
    local dest="$instance_dir/$seg"
    if ! mkdir -p "$(dirname "$dest")" 2>/dev/null; then
      _tgdb_run_privileged mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    fi
    if [ -e "$dest" ] && [ ! -f "$dest" ]; then
      tgdb_fail "AppSpec ${label} 目標必須是檔案，但目前不是：$dest（$service）" 1 || true
      return 1
    fi
    if [ ! -f "$dest" ]; then
      if ! : >"$dest" 2>/dev/null; then
        if ! _tgdb_run_privileged touch "$dest" 2>/dev/null; then
          tgdb_fail "建立檔案失敗：$dest（$service）" 1 || true
          return 1
        fi
      fi
    fi
  done
}

_appspec_config_defs() {
  local service="$1"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_dest_ref="$2"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_tpl_ref="$3"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_mode_ref="$4"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_label_ref="$5"

  out_dest_ref=()
  out_tpl_ref=()
  out_mode_ref=()
  out_label_ref=()

  local raw
  raw="$(appspec_get_all "$service" "config" 2>/dev/null || true)"
  if [ -n "$raw" ]; then
    local line dest_rel
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local -A opts=()
      _appspec_parse_pipe_def "$line" dest_rel opts || true
      [ -n "$dest_rel" ] || continue

      local tpl_rel mode label
      tpl_rel="${opts[template]:-}"
      mode="${opts[mode]:-}"
      label="${opts[label]:-}"

      if [ -z "$tpl_rel" ]; then
        tgdb_fail "AppSpec 設定錯誤（$service）：config 必須指定 template：$dest_rel" 1 || true
        return 1
      fi
      if ! _appspec_instance_rel_path_is_safe "$dest_rel"; then
        tgdb_fail "AppSpec config 不合法（$service）：$dest_rel" 1 || true
        return 1
      fi

      out_dest_ref+=("$dest_rel")
      out_tpl_ref+=("$tpl_rel")
      out_mode_ref+=("$mode")
      out_label_ref+=("$label")
    done <<< "$raw"
    return 0
  fi

  # v1 legacy：單一設定檔
  local config_template config_dest
  config_template="$(appspec_get "$service" "config_template" "")"
  config_dest="$(appspec_get "$service" "config_dest" "")"

  if [ -z "$config_template" ] && [ -z "$config_dest" ]; then
    return 0
  fi
  if [ -z "$config_template" ] || [ -z "$config_dest" ]; then
    tgdb_fail "AppSpec 設定錯誤（$service）：config_template 與 config_dest 必須同時設定" 1 || true
    return 1
  fi
  if ! _appspec_instance_rel_path_is_safe "$config_dest"; then
    tgdb_fail "AppSpec config_dest 不合法（$service）：$config_dest" 1 || true
    return 1
  fi

  local config_mode config_label
  config_mode="$(appspec_get "$service" "config_mode" "")"
  config_label="$(appspec_get "$service" "config_label" "")"

  out_dest_ref+=("$config_dest")
  out_tpl_ref+=("$config_template")
  out_mode_ref+=("$config_mode")
  out_label_ref+=("$config_label")
  return 0
}

_appspec_unit_filename_is_safe() {
  local p="$1"
  [ -n "${p:-}" ] || return 1
  case "$p" in
    /*|*\\*|*..*|*/*) return 1 ;;
  esac
  case "$p" in
    *.container|*.pod) ;;
    *) return 1 ;;
  esac
  return 0
}

_appspec_unit_defs() {
  local service="$1"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_suffix_ref="$2"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_tpl_ref="$3"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_kv_ref="$4"

  out_suffix_ref=()
  out_tpl_ref=()
  out_kv_ref=()

  local raw
  raw="$(appspec_get_all "$service" "unit" 2>/dev/null || true)"
  [ -n "$raw" ] || return 1

  local line unit_id
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local -A opts=()
    _appspec_parse_pipe_def "$line" unit_id opts || true
    [ -n "$unit_id" ] || continue

    local tpl_rel suffix
    tpl_rel="${opts[template]:-}"
    suffix="${opts[suffix]:-}"
    if [ -z "$tpl_rel" ]; then
      tgdb_fail "AppSpec unit 缺少 template（$service）：$unit_id" 1 || true
      return 1
    fi
    if [ -z "$suffix" ]; then
      tgdb_fail "AppSpec unit 缺少 suffix（$service）：$unit_id" 1 || true
      return 1
    fi
    case "$suffix" in
      *.container|*.pod) ;;
      *)
        tgdb_fail "AppSpec unit suffix 必須以 .container 或 .pod 結尾（$service）：$unit_id（suffix=$suffix）" 1 || true
        return 1
        ;;
    esac

    out_suffix_ref+=("$suffix")
    out_tpl_ref+=("$tpl_rel")

    # 將 unit 的其他 opts 當作模板變數（KEY=VALUE），但略過保留鍵。
    local kvs=""
    local k
    for k in "${!opts[@]}"; do
      case "$k" in
        template|suffix) continue ;;
      esac
      _appspec_env_key_is_valid "$k" || continue
      kvs+="${k}=${opts[$k]}"$'\n'
    done
    out_kv_ref+=("$kvs")
  done <<< "$raw"

  [ ${#out_suffix_ref[@]} -gt 0 ] || return 1
  return 0
}

_appspec_resolve_render_unit_defs() {
  local service="$1" quadlet_type="$2"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_suffix_ref="$3"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_tpl_ref="$4"
  # shellcheck disable=SC2178 # out_* 透過 nameref 回傳（shellcheck 誤判）
  local -n out_kv_ref="$5"

  out_suffix_ref=()
  out_tpl_ref=()
  out_kv_ref=()

  case "$quadlet_type" in
    multi)
      local -a resolved_suffixes=() resolved_tpls=() resolved_kvs=()
      _appspec_unit_defs "$service" resolved_suffixes resolved_tpls resolved_kvs || {
        tgdb_fail "AppSpec multi 缺少 unit 定義（$service）。" 1 || true
        return 1
      }
      out_suffix_ref=("${resolved_suffixes[@]}")
      out_tpl_ref=("${resolved_tpls[@]}")
      out_kv_ref=("${resolved_kvs[@]}")
      ;;
    single)
      local quadlet_template
      quadlet_template="$(appspec_get "$service" "quadlet_template" "")"
      if [ -z "$quadlet_template" ]; then
        tgdb_fail "AppSpec 缺少 quadlet_template：$service" 1 || true
        return 1
      fi
      out_suffix_ref+=(".container")
      out_tpl_ref+=("$quadlet_template")
      out_kv_ref+=("")
      ;;
    *)
      tgdb_fail "AppSpec 暫不支援 quadlet_type：$service（quadlet_type=$quadlet_type）" 1 || true
      return 1
      ;;
  esac

  return 0
}

_appspec_apply_render_runtime_options() {
  local service="$1" name="$2" content="$3" selinux_flag="$4" propagation="$5" volume_dir="${6:-}"

  local selinux_pat=""
  local selinux_volume_dir
  selinux_volume_dir="$(appspec_get "$service" "selinux_volume_dir" "skip")"
  if [ -n "${volume_dir:-}" ] && [ "${volume_dir:-}" != "0" ] && [ "$selinux_volume_dir" != "apply" ]; then
    local esc
    esc="$(_appspec_awk_regex_escape "$volume_dir")"
    # 同時略過 volume_dir 根目錄與其子目錄掛載（${volume_dir}/...）
    selinux_pat="!^Volume=${esc}(/|:)"
  fi
  content=$(_quadlet_apply_selinux_to_volumes "$content" "$selinux_flag" "$selinux_pat")

  if [ -n "$propagation" ] && [ "$propagation" != "none" ]; then
    local mount_pat
    mount_pat="$(appspec_get "$service" "mount_propagation_match_pattern" "")"
    content=$(_quadlet_apply_rshared_to_volumes "$content" "$propagation" "$mount_pat")
  fi

  local vol_prop=""
  vol_prop="$(_appspec_ctx_get "$service" "$name" "volume_dir_propagation" "")"
  if [ -z "$vol_prop" ]; then
    local mode def
    mode="$(appspec_get "$service" "volume_dir_propagation" "")"
    def="$(appspec_get "$service" "volume_dir_propagation_default" "none")"
    case "$mode" in
      ask) vol_prop="$def" ;;
      rprivate|private|rshared|shared|rslave|slave|none) vol_prop="$mode" ;;
    esac
  fi

  if [ -n "$vol_prop" ] && [ -n "${volume_dir:-}" ]; then
    local esc pat
    esc="$(_appspec_awk_regex_escape "$volume_dir")"
    # 允許對 ${volume_dir} 與 ${volume_dir}/子路徑 一併套用 propagation
    pat="^Volume=${esc}(/|:)"
    content=$(_quadlet_apply_rshared_to_volumes "$content" "$vol_prop" "$pat")
  fi

  printf '%s\n' "$content"
}

appspec_prepare_instance() {
  local service="$1" _name="$2" _host_port="$3" instance_dir="$4"
  local deploy_mode scope podman_sock_host_path

  deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"
  scope="$(_apps_current_scope 2>/dev/null || printf '%s\n' "user")"
  podman_sock_host_path="$(_appspec_podman_sock_host_path "$service")"
  _appspec_maybe_enable_podman_socket "$service" || true
  _appspec_require_podman_socket_ready "$service" || return 1

  mkdir -p "$instance_dir"

  # 預先寫入保留鍵到 ctx，讓 default_source/avoid 等規則可引用（例如 avoid=host_port）。
  _appspec_ctx_set "$service" "$_name" "container_name" "$_name"
  _appspec_ctx_set "$service" "$_name" "host_port" "$_host_port"
  _appspec_ctx_set "$service" "$_name" "instance_dir" "$instance_dir"
  _appspec_ctx_set "$service" "$_name" "tgdb_deploy_mode" "$deploy_mode"
  _appspec_ctx_set "$service" "$_name" "tgdb_scope" "$scope"
  _appspec_ctx_set "$service" "$_name" "podman_sock_host_path" "$podman_sock_host_path"

  local subdirs_raw
  subdirs_raw="$(appspec_get "$service" "instance_subdirs" "")"
  if [ -n "$subdirs_raw" ]; then
    local -a subdirs=()
    _appspec_parse_subdirs subdirs "$subdirs_raw" "instance_subdirs" || return 1

    local d
    for d in "${subdirs[@]}"; do
      mkdir -p "$instance_dir/$d"
    done
  fi

  _appspec_touch_files "$service" "$instance_dir" "touch_files" || return 1

  _appspec_collect_inputs "$service" "$_name" || return $?
  _appspec_collect_vars "$service" "$_name" || return $?

  # shellcheck disable=SC2034 # cfg_labels 僅用於 _appspec_config_defs 回傳（此處不需要）
  local -a cfg_dests=() cfg_tpls=() cfg_modes=() cfg_labels=()
  _appspec_config_defs "$service" cfg_dests cfg_tpls cfg_modes cfg_labels || return 1

  local user_name pass_word
  user_name="$(_appspec_ctx_get "$service" "$_name" "user_name" "")"
  pass_word="$(_appspec_ctx_get "$service" "$_name" "pass_word" "")"
  local -a kv_args=()
  _appspec_build_render_kv_args kv_args "$service" "$_name"

  local i
  for ((i = 0; i < ${#cfg_dests[@]}; i++)); do
    local tpl_rel dest_rel tpl dest mode
    tpl_rel="${cfg_tpls[$i]}"
    dest_rel="${cfg_dests[$i]}"
    mode="${cfg_modes[$i]:-}"

    tpl="$(_appspec_join_service_path "$service" "$tpl_rel")" || return 1
    if [ ! -f "$tpl" ]; then
      tgdb_fail "找不到 ${service} 設定檔範本：$tpl" 1 || true
      return 1
    fi

    dest="$instance_dir/$dest_rel"
    mkdir -p "$(dirname "$dest")"
    if ! _render_quadlet_template "$tpl" "$_name" "$_host_port" "$instance_dir" "" "$user_name" "$pass_word" "${kv_args[@]}" >"$dest"; then
      tgdb_fail "渲染設定檔範本失敗：$tpl -> $dest" 1 || true
      return 1
    fi

    if [ -n "$mode" ]; then
      if [[ "$mode" =~ ^[0-9]+$ ]]; then
        chmod "$mode" "$dest" 2>/dev/null || true
      else
        tgdb_warn "忽略無效 config mode（$service）：$mode（dest=$dest_rel）"
      fi
    fi

    printf '%s\n' "$dest"
  done

  _appspec_run_hook_scripts "$service" "$_name" "$instance_dir" "$_host_port" "pre_deploy" || return $?
  return 0
}

appspec_render_quadlet() {
  local service="$1" name="$2" host_port="$3" instance_dir="$4" selinux_flag="$5" propagation="$6" volume_dir="${7:-}" _units_dir="${8:-}"

  # 將（可能已由 _deploy_app_core 正規化/補全的）volume_dir 回寫到 ctx，供 success_extra 等提示使用。
  if [ -n "${volume_dir:-}" ]; then
    _appspec_ctx_set "$service" "$name" "volume_dir" "$volume_dir"
  fi

  local quadlet_type
  quadlet_type="$(appspec_get "$service" "quadlet_type" "")"
  if [ "$quadlet_type" = "multi" ] && { [ -z "${_units_dir:-}" ] || [ ! -d "${_units_dir:-}" ]; }; then
    tgdb_fail "AppSpec multi 需要提供輸出目錄（$service）。" 1 || true
    return 1
  fi

  local -a unit_suffixes=() unit_tpls=() unit_kvs=()
  _appspec_resolve_render_unit_defs "$service" "$quadlet_type" unit_suffixes unit_tpls unit_kvs || return 1

  local user_name pass_word
  user_name="$(_appspec_ctx_get "$service" "$name" "user_name" "")"
  pass_word="$(_appspec_ctx_get "$service" "$name" "pass_word" "")"
  local -a kv_args=()
  _appspec_build_render_kv_args kv_args "$service" "$name"

  local rendered_single=""
  local i
  for ((i = 0; i < ${#unit_suffixes[@]}; i++)); do
    local suffix tpl_rel tpl out_fn out_path content
    suffix="${unit_suffixes[$i]}"
    tpl_rel="${unit_tpls[$i]}"
    tpl="$(_appspec_join_service_path "$service" "$tpl_rel")" || return 1
    if [ "$quadlet_type" = "multi" ] && [ ! -f "$tpl" ]; then
      tgdb_fail "找不到 ${service} Quadlet 範本：$tpl" 1 || true
      return 1
    fi

    out_fn="${name}${suffix}"
    if ! _appspec_unit_filename_is_safe "$out_fn"; then
      tgdb_fail "AppSpec unit 產生的檔名不合法（$service）：$out_fn" 1 || true
      return 1
    fi

    local -a unit_kv_args=("${kv_args[@]}")
    local unit_kvs_raw="${unit_kvs[$i]}"
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && unit_kv_args+=("$line")
    done <<< "$unit_kvs_raw"

    content=$(_render_quadlet_template "$tpl" "$name" "$host_port" "$instance_dir" "$volume_dir" "$user_name" "$pass_word" "${unit_kv_args[@]}")
    content="$(_appspec_apply_render_runtime_options "$service" "$name" "$content" "$selinux_flag" "$propagation" "$volume_dir")"

    if [ "$quadlet_type" = "multi" ]; then
      out_path="${_units_dir}/${out_fn}"
      _appspec_write_staging_unit_file "$out_path" "$content" || return 1
    else
      rendered_single="$content"
    fi
  done

  if [ "$quadlet_type" = "multi" ]; then
    printf '%s\n' "$_units_dir"
  else
    printf '%s\n' "$rendered_single"
  fi
}

appspec_ask_mount_options() {
  local service="$1" _instance_dir="$2" name="${3:-}"

  local selinux_flag="none"
  if declare -F _apps_default_selinux_flag >/dev/null 2>&1; then
    selinux_flag="$(_apps_default_selinux_flag 1)"
  fi

  local mode
  mode="$(appspec_get "$service" "mount_propagation" "")"
  [ -n "$mode" ] || { printf '%s %s\n' "none" "$selinux_flag"; return 0; }

  local chosen="none"
  case "$mode" in
    ask)
      local ask_value default_value prompt default_yn
      ask_value="$(appspec_get "$service" "mount_propagation_ask_value" "rshared")"
      default_value="$(appspec_get "$service" "mount_propagation_default" "none")"
      prompt="$(appspec_get "$service" "mount_propagation_prompt" "")"
      if [ -z "$prompt" ]; then
        prompt="是否為資料掛載添加 :${ask_value}？(Y/n，預設 N，輸入 0 取消): "
      fi

      default_yn="N"
      if [ "$default_value" = "$ask_value" ]; then
        default_yn="Y"
      fi

      if ui_is_interactive; then
        if ui_confirm_yn "$prompt" "$default_yn"; then
          chosen="$ask_value"
        else
          local rc=$?
          if [ "$rc" -eq 2 ]; then
            return 2
          fi
          chosen="none"
        fi
      else
        if [ "$default_value" = "$ask_value" ]; then
          chosen="$ask_value"
        else
          chosen="none"
        fi
      fi
      ;;
    none|rprivate|private|rshared|shared|rslave|slave)
      chosen="$mode"
      ;;
    *)
      tgdb_warn "忽略無效 mount_propagation（$service）：$mode"
      chosen="none"
      ;;
  esac

  if [ -n "${name:-}" ]; then
    _appspec_ctx_set "$service" "$name" "mount_propagation" "$chosen"
  fi

  printf '%s %s\n' "$chosen" "$selinux_flag"
}

appspec_ask_volume_dir() {
  local service="$1" _instance_dir="$2" name="${3:-}"
  local deploy_mode
  deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"

  local prompt
  prompt="$(appspec_get "$service" "volume_dir_prompt" "")"
  if [ -z "$prompt" ]; then
    prompt="Volume 資料目錄"
  fi

  local default_volume_dir="0"
  local volume_dir=""

  local backup_root
  if declare -F tgdb_backup_root >/dev/null 2>&1; then
    backup_root="$(tgdb_backup_root)"
  else
    backup_root="${TGDB_BACKUP_ROOT:-$(dirname "${TGDB_DIR:-$HOME/.tgdb/app}")}"
  fi

  while true; do
    read -r -e -p "${prompt} (預設: 0=自動建立 ${backup_root}/volume/${service}/${name:-$service}): " volume_dir
    volume_dir=${volume_dir:-$default_volume_dir}

    if [ "$volume_dir" = "0" ]; then
      break
    fi

    if _apps_test "$deploy_mode" -e "$volume_dir" && ! _apps_test "$deploy_mode" -d "$volume_dir"; then
      tgdb_err "$volume_dir 不是資料夾，請重新輸入。"
      continue
    fi

    if _apps_test "$deploy_mode" -d "$volume_dir" && { ! _apps_test "$deploy_mode" -r "$volume_dir" || ! _apps_test "$deploy_mode" -w "$volume_dir"; }; then
      tgdb_err "目前使用者對 $volume_dir 沒有讀寫權限，請調整權限或輸入其他目錄。"
      continue
    fi
    break
  done

  # 是否為 volume_dir 掛載添加 propagation 標籤（例如 :rshared）
  local mode
  mode="$(appspec_get "$service" "volume_dir_propagation" "")"
  if [ -n "$mode" ]; then
    local chosen="none"
    case "$mode" in
      ask)
        local def prompt_default ask_value
        def="$(appspec_get "$service" "volume_dir_propagation_default" "none")"
        ask_value="$(appspec_get "$service" "volume_dir_propagation_ask_value" "rshared")"
        case "$ask_value" in
          rprivate|private|rshared|shared|rslave|slave) ;;
          *)
            tgdb_warn "忽略無效 volume_dir_propagation_ask_value（$service）：$ask_value（已改用 rshared）"
            ask_value="rshared"
            ;;
        esac
        case "$def" in
          rshared|shared|rslave|slave|rprivate|private) prompt_default="Y" ;;
          *) prompt_default="N" ;;
        esac

        if ui_is_interactive; then
          if ui_confirm_yn "是否為 ${prompt} 掛載添加 :${ask_value}（即時映射掛載點）？(Y/n，預設 ${prompt_default}，輸入 0 取消): " "$prompt_default"; then
            chosen="$ask_value"
          else
            local rc=$?
            if [ "$rc" -eq 2 ]; then
              return 2
            fi
            chosen="none"
          fi
        else
          chosen="$def"
        fi
        ;;
      rprivate|private|rshared|shared|rslave|slave|none)
        chosen="$mode"
        ;;
      *)
        tgdb_warn "忽略無效 volume_dir_propagation（$service）：$mode"
        ;;
    esac

    if [ -n "${name:-}" ]; then
      _appspec_ctx_set "$service" "$name" "volume_dir_propagation" "$chosen"
    fi
  fi

  if [ -n "${name:-}" ]; then
    _appspec_ctx_set "$service" "$name" "volume_dir" "$volume_dir"
  fi

  printf '%s\n' "$volume_dir"
}
