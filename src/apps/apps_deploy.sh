#!/bin/bash

# Apps：部署流程（由 src/apps-p.sh 載入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_apps_require_editor() {
  if ensure_editor; then
    return 0
  fi
  tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || return $?
}

_apps_config_label_for_edit() {
  local service="$1"

  if _app_fn_exists "$service" config_label; then
    _app_invoke "$service" config_label 2>/dev/null || true
    return 0
  fi

  printf '%s\n' ""
  return 0
}

_apps_confirm_custom_quadlet_and_config() {
  local config_label="$1"

  local edit_rc=0
  if [ -n "$config_label" ]; then
    ui_confirm_yn "是否自訂 Quadlet 與 $config_label？(Y/n，預設 N，輸入 0 取消): " "N" || edit_rc=$?
  else
    ui_confirm_yn "是否自訂 Quadlet？(Y/n，預設 N，輸入 0 取消): " "N" || edit_rc=$?
  fi

  return "$edit_rc"
}

_apps_collect_quadlet_unit_files() {
  local units_dir="$1"
  # shellcheck disable=SC2178 # out_ref 透過 nameref 回傳（shellcheck 誤判）
  local -n out_ref="$2"

  out_ref=()
  [ -n "${units_dir:-}" ] || return 0

  local had_nullglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  # shellcheck disable=SC2034 # out_ref 透過 nameref 回傳（shellcheck 誤判）
  out_ref=("$units_dir"/*.container "$units_dir"/*.pod)
  if [ "$had_nullglob" -eq 0 ]; then
    shopt -u nullglob
  fi
  return 0
}

_apps_collect_publish_ports_from_unit_content() {
  # 從 Quadlet 內容中擷取所有 PublishPort 的「主機端埠號」。
  # - 支援格式：
  #   - PublishPort=<hostPort>:<containerPort>
  #   - PublishPort=<ip>:<hostPort>:<containerPort>
  #   - PublishPort=0.0.0.0:<hostPort>:<containerPort>/tcp
  # - 若無法解析（例如 IPv6 或非數字），則略過。
  local unit_content="$1"
  # shellcheck disable=SC2178 # out_ref 透過 nameref 回傳（shellcheck 誤判）
  local -n out_ref="$2"

  out_ref=()

  local line value host_p
  while IFS= read -r line; do
    case "$line" in
      PublishPort=*)
        value="${line#PublishPort=}"
        value="${value%%/*}"

        host_p=""
        if [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+: ]]; then
          host_p="${value#*:}"
          host_p="${host_p%%:*}"
        elif [[ "$value" =~ ^[0-9]+: ]]; then
          host_p="${value%%:*}"
        fi

        if [[ "$host_p" =~ ^[0-9]+$ ]] && [ "$host_p" -gt 0 ] 2>/dev/null; then
          out_ref+=("$host_p")
        fi
        ;;
    esac
  done <<< "$unit_content"
}

_apps_fail_if_publish_ports_in_use() {
  local service="$1"
  shift || true

  [ "$#" -gt 0 ] || return 0
  declare -F _is_port_in_use >/dev/null 2>&1 || return 0

  local -A seen=()
  local -a used=()

  local p
  for p in "$@"; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    [ -n "${seen[$p]+x}" ] && continue
    seen[$p]=1
    if _is_port_in_use "$p"; then
      used+=("$p")
    fi
  done

  if [ ${#used[@]} -gt 0 ]; then
    tgdb_fail "PublishPort 埠號已被占用（$service）：${used[*]}；請調整埠號或編輯 Quadlet 後再部署。" 1 || return $?
  fi
  return 0
}

_maybe_edit_app_record() {
  local service="$1" quad_path="$2" unit_var="$3"
  shift 3 || true
  local -a config_paths=("$@")

  local config_label=""
  if [ ${#config_paths[@]} -gt 0 ]; then
    config_label="$(_apps_config_label_for_edit "$service")"
  fi

  if ! _apps_confirm_custom_quadlet_and_config "$config_label"; then
    local edit_rc=$?
    if [ "$edit_rc" -eq 2 ]; then
      return 2
    fi
    return 0
  fi

  _apps_require_editor || return $?
  "$EDITOR" "$quad_path" "${config_paths[@]}"
  printf -v "$unit_var" '%s' "$(cat "$quad_path")"
}

_maybe_edit_app_record_multi() {
  local service="$1" units_dir="$2"
  shift 2 || true

  local -a config_paths=()
  local cp
  for cp in "$@"; do
    [ -n "$cp" ] && [ -f "$cp" ] && config_paths+=("$cp")
  done

  local config_label=""
  if [ ${#config_paths[@]} -gt 0 ]; then
    config_label="$(_apps_config_label_for_edit "$service")"
  fi

  if ! _apps_confirm_custom_quadlet_and_config "$config_label"; then
    local edit_rc=$?
    if [ "$edit_rc" -eq 2 ]; then
      return 2
    fi
    return 0
  fi

  _apps_require_editor || return $?

  local -a files=()
  _apps_collect_quadlet_unit_files "$units_dir" files

  if [ ${#files[@]} -eq 0 ]; then
    tgdb_fail "找不到可編輯的 Quadlet 單元檔案：$units_dir" 1 || return $?
  fi

  "$EDITOR" "${files[@]}" "${config_paths[@]}"
}

_post_deploy_app() {
  local service="$1" name="$2"
  if _app_fn_exists "$service" post_deploy; then
    _app_invoke "$service" post_deploy "$name"
  fi
}

_instance_publish_is_loopback() {
  local service="$1" name="$2"
  local d
  d="$(_service_quadlet_dir "$service")"

  [ -d "$d" ] || return 2

  local -a files=()
  if [ -f "$d/$name.container" ]; then
    files+=("$d/$name.container")
  fi

  local f=""
  while IFS= read -r -d $'\0' f; do
    files+=("$f")
  done < <(find "$d" -maxdepth 1 -type f \( -name "$name.pod" -o -name "$name.container" -o -name "$name-*.container" \) -print0 2>/dev/null)

  if [ ${#files[@]} -eq 0 ]; then
    return 2
  fi

  for f in "${files[@]}"; do
    if grep -q '^PublishPort=127\.0\.0\.1:' "$f" 2>/dev/null; then
      return 0
    fi
  done

  return 1
}

_apps_service_access_policy() {
  local service="$1"
  local policy=""

  if declare -F appspec_has_service >/dev/null 2>&1 && declare -F appspec_get >/dev/null 2>&1; then
    if appspec_has_service "$service"; then
      policy="$(appspec_get "$service" "access_policy" "")"
    fi
  fi

  case "${policy,,}" in
    local_only)
      printf '%s\n' "local_only"
      ;;
    *)
      printf '%s\n' "default"
      ;;
  esac
}

_print_deploy_success() {
  local service="$1" name="$2" host_port="$3" instance_dir="$4"
  local publish_loopback=0
  local access_policy="default"
  if _instance_publish_is_loopback "$service" "$name"; then
    publish_loopback=1
  fi
  access_policy="$(_apps_service_access_policy "$service")"

  local display_name
  display_name="$(_apps_service_display_name "$service")"

  # 提供統一的部署後存取提示（同時讓 AppSpec success_extra / app print_deploy_success 可選擇讀取這些 env）。
  if [ "$publish_loopback" = "1" ]; then
    export TGDB_APP_PUBLISH_SCOPE="loopback"
    export TGDB_APP_ACCESS_HOST="127.0.0.1"
    export TGDB_APP_ACCESS_PORT="$host_port"
  else
    local ipv4_address="未知"
    if declare -F get_ipv4_address >/dev/null 2>&1; then
      ipv4_address="$(get_ipv4_address)"
    fi
    export TGDB_APP_PUBLISH_SCOPE="public"
    export TGDB_APP_ACCESS_HOST="$ipv4_address"
    export TGDB_APP_ACCESS_PORT="$host_port"
  fi

  # 先印出共用預設提示，再由 app/spec 補充額外提醒。
  if [ "$publish_loopback" = "1" ]; then
    echo "✅ $display_name 啟動中，可用「查看單元日誌」追蹤：容器 $name，訪問 http://${TGDB_APP_ACCESS_HOST:-127.0.0.1}:${TGDB_APP_ACCESS_PORT:-$host_port}（僅本機回環），目錄 $instance_dir"
  else
    local ipv4_address="${TGDB_APP_ACCESS_HOST:-未知}"
    echo "✅ $display_name 啟動中，可用「查看單元日誌」追蹤：容器 $name，訪問 ${ipv4_address}:${TGDB_APP_ACCESS_PORT:-$host_port}，目錄 $instance_dir"
  fi

  if _app_fn_exists "$service" print_deploy_success; then
    _app_invoke "$service" print_deploy_success "$name" "$host_port" "$instance_dir"
  fi

  # PublishPort 綁定 127.0.0.1 時，補充安全存取提示避免誤解可直接對外連線。
  if [ "$publish_loopback" = "1" ]; then
    if [ "$access_policy" = "local_only" ]; then
      echo "⚠️ 安全提醒：$display_name 建議僅本機訪問，不建議反向代理到公網。"
      echo "ℹ️ 建議：維持 127.0.0.1 存取，或使用 SSH 本機埠轉發。"
      echo "   - 例：ssh -L 8080:127.0.0.1:$host_port user@server"
    else
      echo "ℹ️ 注意：此服務目前僅綁定本機回環埠 127.0.0.1:$host_port（外部網路無法直接訪問）。"
      echo "ℹ️ 建議：使用 Nginx 反向代理（HTTPS）對外提供服務，或透過 VS Code/SSH 本機埠轉發安全訪問。"
      echo "   - 例：ssh -L 8080:127.0.0.1:$host_port user@server"
    fi
  fi

  unset TGDB_APP_PUBLISH_SCOPE TGDB_APP_ACCESS_HOST TGDB_APP_ACCESS_PORT
}

_is_app_name_duplicate() {
  local name="$1"

  if [ -d "$TGDB_DIR/$name" ]; then
    return 0
  fi

  local user_units_dir
  user_units_dir="$(rm_user_units_dir)"
  if [ -d "$user_units_dir" ]; then
    if [ -f "$user_units_dir/$name.container" ] || \
       [ -f "$user_units_dir/$name.service" ] || \
       [ -f "$user_units_dir/container-$name.service" ]; then
      return 0
    fi
  fi

  local persist_dir
  persist_dir="$(rm_persist_config_dir)"
  if [ -d "$persist_dir" ]; then
    if find "$persist_dir" -maxdepth 3 -type f \( \
        -path "*/quadlet/$name.container" -o \
        -path "*/configs/$name.*" \
      \) -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  fi

  return 1
}

get_next_available_app_name() {
  local base_name="$1"
  local i=1
  local target_name="$base_name"

  while _is_app_name_duplicate "$target_name"; do
    i=$((i + 1))
    target_name="${base_name}${i}"
  done

  printf '%s\n' "$target_name"
}

_cleanup_staging_dirs() {
  local staging_instance_dir="$1"
  local staging_units_dir="$2"

  if [ -n "${staging_instance_dir:-}" ] && [ -d "${staging_instance_dir:-}" ]; then
    rm -rf "$staging_instance_dir" 2>/dev/null || true
  fi
  if [ -n "${staging_units_dir:-}" ] && [ -d "${staging_units_dir:-}" ]; then
    rm -rf "$staging_units_dir" 2>/dev/null || true
  fi
}

_extract_existing_files_from_output() {
  local output="$1"
  local line

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # 去除可能的 CR（例如：不同環境換行）
    line="${line%$'\r'}"
    if [ -f "$line" ]; then
      printf '%s\n' "$line"
    fi
  done <<< "$output"
}

_extract_last_nonempty_line_from_output() {
  local output="$1"
  local line best=""

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line="${line%$'\r'}"
    best="$line"
  done <<< "$output"

  printf '%s\n' "$best"
}

_apps_get_mount_options_line() {
  local service="$1" instance_dir="$2" name="${3:-}"

  local mount_out="" mount_rc=0
  if _app_fn_exists "$service" ask_mount_options; then
    mount_out="$(_app_invoke "$service" ask_mount_options "$instance_dir" "$name")" || mount_rc=$?
  else
    mount_out="$(_apps_default_mount_options "$instance_dir")" || mount_rc=$?
  fi
  if [ "$mount_rc" -eq 2 ]; then
    return 2
  fi
  if [ "$mount_rc" -ne 0 ]; then
    tgdb_fail "取得掛載選項失敗（$service）。" 1 || return $?
  fi

  _extract_last_nonempty_line_from_output "$mount_out"
}

_apps_ensure_volume_subdirs() {
  local service="$1" volume_dir="$2"

  [ -n "${volume_dir:-}" ] || return 0
  [ "${volume_dir:-}" != "0" ] || return 0
  declare -F appspec_get >/dev/null 2>&1 || return 0

  local raw
  raw="$(appspec_get "$service" "volume_subdirs" "")"
  [ -n "$raw" ] || return 0

  local seg
  for seg in $raw; do
    [ -n "$seg" ] || continue

    if declare -F _appspec_instance_rel_path_is_safe >/dev/null 2>&1; then
      if ! _appspec_instance_rel_path_is_safe "$seg"; then
        tgdb_fail "AppSpec volume_subdirs 不合法（$service）：$seg" 1 || return $?
      fi
    else
      case "$seg" in
        /*|*\\*|*..*)
          tgdb_fail "AppSpec volume_subdirs 不合法（$service）：$seg" 1 || return $?
          ;;
      esac
    fi

    local target="$volume_dir/$seg"
    if [ -e "$target" ] && [ ! -d "$target" ]; then
      tgdb_fail "volume_subdirs 目標不是資料夾（$service）：$target" 1 || return $?
    fi
    if ! mkdir -p "$target" 2>/dev/null; then
      tgdb_fail "無法建立 volume_subdirs 目錄（$service）：$target（請確認路徑權限）" 1 || return $?
    fi
  done
}

_deploy_app_core() {
  local service="$1" name="$2" host_port="$3" instance_dir="$4" propagation="${5:-none}" selinux_flag="${6:-none}" volume_dir="${7:-}"

  # volume_dir：由 AppSpec 決定是否啟用（uses_volume_dir=1）。
  local needs_volume_dir=0
  if _apps_service_uses_volume_dir "$service"; then
    needs_volume_dir=1
  fi

  if [ "$needs_volume_dir" -eq 1 ]; then
    # 預設採用 ${BACKUP_ROOT}/volume/${service}/${name}（不納入備份；避免 /mnt 需要 sudo 的問題）
    local backup_root default_volume_dir
    if declare -F tgdb_backup_root >/dev/null 2>&1; then
      backup_root="$(tgdb_backup_root)"
    else
      backup_root="${TGDB_BACKUP_ROOT:-$(dirname "${TGDB_DIR:-$HOME/.tgdb/app}")}"
    fi
    default_volume_dir="$backup_root/volume/${service}/${name}"

    if [ -z "${volume_dir:-}" ] || [ "${volume_dir:-}" = "0" ] || [ "${volume_dir:-}" = "$default_volume_dir" ]; then
      if declare -F ensure_app_volume_dir >/dev/null 2>&1; then
        volume_dir="$(ensure_app_volume_dir "$service" "$name")" || return $?
      else
        volume_dir="$default_volume_dir"
      fi
    fi

    if [ -n "${volume_dir:-}" ] && [ "${volume_dir:-}" != "0" ]; then
      # 若是自訂路徑，仍嘗試建立（避免第一次部署就因目錄不存在而失敗）
      if [ -e "$volume_dir" ] && [ ! -d "$volume_dir" ]; then
        tgdb_fail "volume_dir 不是資料夾：$volume_dir" 1 || return $?
      fi
      if [ ! -d "$volume_dir" ]; then
        if ! mkdir -p "$volume_dir" 2>/dev/null; then
          tgdb_fail "無法建立 volume_dir：$volume_dir（請確認路徑權限）" 1 || return $?
        fi
      fi
      if [ -d "$volume_dir" ] && { [ ! -r "$volume_dir" ] || [ ! -w "$volume_dir" ]; }; then
        tgdb_fail "目前使用者對 $volume_dir 沒有讀寫權限，請調整權限或改用其他目錄。" 1 || return $?
      fi

      # 若 AppSpec 宣告 volume_subdirs，部署前先建立，避免 Quadlet 掛載不存在路徑而啟動失敗。
      _apps_ensure_volume_subdirs "$service" "$volume_dir" || return $?
    fi
  fi

  local staging_instance_dir
  staging_instance_dir="$(mktemp -d "${TMPDIR:-/tmp}/tgdb_${service}_${name}.XXXXXX")"
  local staging_units_dir
  staging_units_dir="$(mktemp -d "${TMPDIR:-/tmp}/tgdb_${service}_${name}.units.XXXXXX")"

  local -a config_paths=()
  # 注意：不可用 command substitution 取得回傳值，否則 prepare_instance 在 subshell 執行，
  # 會導致其內部 export 的環境變數（例如密碼、額外埠號）無法傳遞到後續 render_quadlet。
  local prep_out_file prep_out=""
  prep_out_file="$(mktemp "${TMPDIR:-/tmp}/tgdb_${service}_${name}.prepare.XXXXXX.out")"
  _app_invoke "$service" prepare_instance "$name" "$host_port" "$staging_instance_dir" >"$prep_out_file"
  local prep_rc=$?
  prep_out="$(cat "$prep_out_file" 2>/dev/null || true)"
  rm -f "$prep_out_file" 2>/dev/null || true
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && config_paths+=("$line")
  done < <(_extract_existing_files_from_output "$prep_out")
  if [ "$prep_rc" -eq 2 ]; then
    _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
    if [ "${TGDB_CLI_MODE:-0}" != "1" ]; then
      echo "操作已取消。"
      ui_pause "按任意鍵返回..."
      return 0
    fi
    return 2
  fi
  if [ "$prep_rc" -ne 0 ]; then
    _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
    return "$prep_rc"
  fi

  local rendered
  rendered=$(_app_invoke "$service" render_quadlet "$name" "$host_port" "$instance_dir" "$selinux_flag" "$propagation" "$volume_dir" "$staging_units_dir")
  local render_rc=$?
  if [ "$render_rc" -eq 2 ]; then
    _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
    if [ "${TGDB_CLI_MODE:-0}" != "1" ]; then
      echo "操作已取消。"
      ui_pause "按任意鍵返回..."
      return 0
    fi
    return 2
  fi
  if [ "$render_rc" -ne 0 ]; then
    _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
    return "$render_rc"
  fi

  local is_multi=0 units_dir="" unit=""
  if [ -n "${rendered:-}" ] && [ -d "${rendered:-}" ]; then
    local -a rendered_units=()
    _apps_collect_quadlet_unit_files "$rendered" rendered_units
    if [ ${#rendered_units[@]} -gt 0 ]; then
      is_multi=1
      units_dir="$rendered"
    fi
  fi
  if [ "$is_multi" -eq 0 ]; then
    unit="$rendered"
  fi

  if [ "${TGDB_CLI_MODE:-0}" != "1" ]; then
    if [ "$is_multi" -eq 1 ]; then
      _maybe_edit_app_record_multi "$service" "$units_dir" "${config_paths[@]}" || {
        local edit_rc=$?
        if [ "$edit_rc" -eq 2 ]; then
          _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
          echo "操作已取消。"
          return 0
        fi
        _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
        return "$edit_rc"
      }
    else
      local tmp_quad
      tmp_quad="$(mktemp "${TMPDIR:-/tmp}/tgdb_${service}_${name}.XXXXXX.container")"
      _write_file "$tmp_quad" "$unit"
      _maybe_edit_app_record "$service" "$tmp_quad" unit "${config_paths[@]}" || {
        local edit_rc=$?
        rm -f "$tmp_quad" 2>/dev/null || true
        if [ "$edit_rc" -eq 2 ]; then
          _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
          echo "操作已取消。"
          return 0
        fi
        _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
        return "$edit_rc"
      }
      rm -f "$tmp_quad" 2>/dev/null || true
    fi
  fi

  # 預檢查：避免因 PublishPort 衝突導致 systemd 啟動失敗。
  # - 必須在「允許使用者編輯 Quadlet」之後執行，才會反映使用者的最終設定。
  if [ "$is_multi" -eq 1 ]; then
    local -a final_ports=()
    local -a files=()
    _apps_collect_quadlet_unit_files "$units_dir" files
    local f
    for f in "${files[@]}"; do
      [ -f "$f" ] || continue
      local -a ports=()
      _apps_collect_publish_ports_from_unit_content "$(cat "$f" 2>/dev/null || true)" ports
      if [ ${#ports[@]} -gt 0 ]; then
        final_ports+=("${ports[@]}")
      fi
    done
    _apps_fail_if_publish_ports_in_use "$service" "${final_ports[@]}" || {
      _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
      return 1
    }
  else
    local -a ports=()
    _apps_collect_publish_ports_from_unit_content "$unit" ports
    _apps_fail_if_publish_ports_in_use "$service" "${ports[@]}" || {
      _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
      return 1
    }
  fi

  mkdir -p "$instance_dir"
  if [ -d "$staging_instance_dir" ]; then
    cp -a "$staging_instance_dir/." "$instance_dir/" 2>/dev/null || \
      cp -r "$staging_instance_dir/." "$instance_dir/" 2>/dev/null || true
  fi

  local unit_files=()
  if [ "$is_multi" -eq 1 ]; then
    _apps_collect_quadlet_unit_files "$units_dir" unit_files
    if [ ${#unit_files[@]} -eq 0 ]; then
      tgdb_fail "找不到可部署的 Quadlet 單元檔案：$units_dir" 1 || return $?
    fi
    if ! _install_quadlet_units_from_files "${unit_files[@]}"; then
      _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
      return 1
    fi
  else
    if ! _install_unit_and_enable "$name" "$unit"; then
      _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
      return 1
    fi
  fi
  _post_deploy_app "$service" "$name"

  if [ "$is_multi" -eq 1 ]; then
    local record_dir
    record_dir="$(_service_quadlet_dir "$service")"
    local rf
    for rf in "${unit_files[@]}"; do
      local record_path
      record_path="$record_dir/$(basename "$rf")"
      _write_file "$record_path" "$(cat "$rf")"
    done
  else
    local record_quad
    record_quad="$(_service_quadlet_dir "$service")/$name.container"
    _write_file "$record_quad" "$unit"
  fi
  if [ ${#config_paths[@]} -gt 0 ]; then
    local -a record_cfgs=()
    local record_out record_rc=0
    record_out="$(_app_invoke "$service" record_config_paths "$name" 2>/dev/null)" || record_rc=$?
    if [ "$record_rc" -ne 0 ]; then
      _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
      tgdb_fail "取得設定檔紀錄路徑失敗（$service/$name）。" 1 || return $?
    fi

    local line
    while IFS= read -r line; do
      [ -n "$line" ] && record_cfgs+=("$line")
    done <<< "$record_out"

    if [ ${#record_cfgs[@]} -ne ${#config_paths[@]} ]; then
      _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"
      tgdb_fail "設定檔紀錄路徑數量不一致（$service/$name）：config=${#config_paths[@]} record=${#record_cfgs[@]}" 1 || return $?
    fi

    local i
    for ((i = 0; i < ${#config_paths[@]}; i++)); do
      local src="${config_paths[$i]}"
      local dst="${record_cfgs[$i]}"
      if [ -z "$src" ] || [ ! -f "$src" ]; then
        continue
      fi
      [ -n "$dst" ] || continue
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
    done
  fi

  _cleanup_staging_dirs "$staging_instance_dir" "$staging_units_dir"

  _print_deploy_success "$service" "$name" "$host_port" "$instance_dir"
  if [ "${TGDB_CLI_MODE:-0}" != "1" ]; then
    ui_pause "按任意鍵返回..."
  fi
}

_deploy_app_cli_quick() {
  local service="$1" name="$2" host_port="$3" instance_dir="$4"
  shift 4 || true

  if _app_fn_exists "$service" cli_quick; then
    _app_invoke "$service" cli_quick "$name" "$host_port" "$instance_dir" "$@"
    return $?
  fi

  local propagation="none" selinux_flag="none"
  local mount_line=""
  mount_line="$(_apps_get_mount_options_line "$service" "$instance_dir" "$name")" || {
    local mount_rc=$?
    if [ "$mount_rc" -eq 2 ]; then
      return 2
    fi
    return "$mount_rc"
  }
  if [ -n "$mount_line" ]; then
    IFS=' ' read -r propagation selinux_flag <<< "$mount_line"
  fi

  local volume_dir=""
  if _apps_service_uses_volume_dir "$service"; then
    volume_dir="${1:-}"
  fi

  _deploy_app_core "$service" "$name" "$host_port" "$instance_dir" "$propagation" "$selinux_flag" "$volume_dir"
}

_deploy_app_quick() {
  local service="$1"

  local default_name
  default_name=$(get_next_available_app_name "$service")
  while true; do
    read -r -e -p "容器名稱 (預設: $default_name): " name
    name=${name:-$default_name}
    if _is_app_name_duplicate "$name"; then
      tgdb_err "已存在相同名稱：$name，請輸入其他名稱。"
      default_name=$(get_next_available_app_name "$service")
      continue
    fi
    break
  done

  local base_port default_port host_port=""
  base_port=$(_app_invoke "$service" default_base_port)
  if [ "$base_port" -gt 0 ] 2>/dev/null; then
    default_port=$(get_next_available_port "$base_port")
  else
    default_port=""
  fi

  host_port="$(prompt_available_port "對外埠" "$default_port")" || {
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "操作已取消。"
      ui_pause "按任意鍵返回..."
      return 0
    fi
    return 1
  }

  local instance_dir
  instance_dir="$TGDB_DIR/$name"
  echo "資料目錄：$instance_dir"

  local propagation="none" selinux_flag="none"
  local mount_line=""
  mount_line="$(_apps_get_mount_options_line "$service" "$instance_dir" "$name")" || {
    local mount_rc=$?
    if [ "$mount_rc" -eq 2 ]; then
      echo "操作已取消。"
      return 0
    fi
    return "$mount_rc"
  }
  if [ -n "$mount_line" ]; then
    IFS=' ' read -r propagation selinux_flag <<< "$mount_line"
  fi

  local volume_dir=""
  if _app_fn_exists "$service" ask_volume_dir; then
    # 注意：不可用 command substitution 取得回傳值，否則 ask_volume_dir 在 subshell 執行，
    # 會導致其內部設定的狀態（例如 AppSpec 記錄的 volume_dir_propagation）無法傳遞到後續 render_quadlet。
    local vol_out_file vol_out=""
    vol_out_file="$(mktemp "${TMPDIR:-/tmp}/tgdb_${service}_${name}.volume.XXXXXX.out")"
    _app_invoke "$service" ask_volume_dir "$instance_dir" "$name" >"$vol_out_file"
    local vol_rc=$?
    vol_out="$(cat "$vol_out_file" 2>/dev/null || true)"
    rm -f "$vol_out_file" 2>/dev/null || true
    if [ "$vol_rc" -eq 2 ]; then
      echo "操作已取消。"
      ui_pause "按任意鍵返回..."
      return 0
    fi
    if [ "$vol_rc" -ne 0 ]; then
      return "$vol_rc"
    fi
    volume_dir="$(_extract_last_nonempty_line_from_output "$vol_out")"
  fi

  _deploy_app_core "$service" "$name" "$host_port" "$instance_dir" "$propagation" "$selinux_flag" "$volume_dir"
}
