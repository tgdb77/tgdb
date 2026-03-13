#!/bin/bash

# Apps：紀錄/還原與 config/quadlet 管理（由 src/apps-p.sh 載入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_service_config_dir() {
  rm_service_configs_dir "$1"
}

_service_quadlet_dir() {
  rm_service_quadlet_dir "$1"
}

_find_quadlet_path() {
  local d
  d=$(_service_quadlet_dir "$1")
  if [ -f "$d/$2.container" ]; then
    echo "$d/$2.container"
    return 0
  fi
  return 1
}

_app_deploy_from_record_single() {
  local service="$1" name="$2"
  shift 2 || true

  local quad
  quad=$(_find_quadlet_path "$service" "$name") || { tgdb_err "找不到 Quadlet 紀錄"; ui_pause; return 1; }
  local unit_content
  unit_content="$(cat "$quad")"

  local instance_dir="$TGDB_DIR/$name"
  if [ "$#" -gt 0 ]; then
    local sub
    for sub in "$@"; do
      [ -n "$sub" ] && mkdir -p "$instance_dir/$sub"
    done
  else
    mkdir -p "$instance_dir"
  fi

  local -a cfgs=()
  if _app_fn_exists "$service" record_config_paths; then
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && [ -f "$line" ] && cfgs+=("$line")
    done < <(_app_invoke "$service" record_config_paths "$name" 2>/dev/null || true)
  fi

  if [ ${#cfgs[@]} -gt 0 ]; then
    if _app_fn_exists "$service" copy_config_to_instance; then
      local cfg
      for cfg in "${cfgs[@]}"; do
        _app_invoke "$service" copy_config_to_instance "$cfg" "$instance_dir" || true
      done
    else
      local cfg
      for cfg in "${cfgs[@]}"; do
        cp "$cfg" "$instance_dir/" 2>/dev/null || true
      done
    fi
  fi

  if ! _install_unit_and_enable "$name" "$unit_content"; then
    tgdb_err "從紀錄部署失敗：$name（單元啟用失敗）"
    ui_pause
    return 1
  fi
  _post_deploy_app "$service" "$name"

  local host_port=""
  host_port="$(_app_extract_primary_host_port_from_unit_content "$unit_content" 2>/dev/null || true)"
  if [[ "$host_port" =~ ^[0-9]+$ ]] && [ "$host_port" -gt 0 ] 2>/dev/null; then
    _print_deploy_success "$service" "$name" "$host_port" "$instance_dir"
  else
    echo "✅ 已從紀錄部署：$name"
  fi
  ui_pause
}

_app_deploy_from_record_multi() {
  local service="$1" name="$2"
  shift 2 || true

  local -a unit_basenames=()
  local -a mkdir_subdirs=()
  local -a chown_subdirs=()
  local chown_uidgid=""

  local section="units"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mkdir)
        section="mkdir"
        shift
        continue
        ;;
      --chown)
        chown_uidgid="${2:-}"
        section="chown"
        shift 2 || true
        continue
        ;;
      --)
        shift
        break
        ;;
    esac

    case "$section" in
      units) unit_basenames+=("$1") ;;
      mkdir) mkdir_subdirs+=("$1") ;;
      chown) chown_subdirs+=("$1") ;;
    esac
    shift
  done

  local display_name
  display_name="$(_apps_service_display_name "$service")"

  if [ ${#unit_basenames[@]} -eq 0 ]; then
    tgdb_err "未提供任何 $display_name Quadlet 單元檔名：$name"
    ui_pause
    return 1
  fi

  local qdir
  qdir="$(_service_quadlet_dir "$service")"
  local -a unit_files=()
  local -a missing=()
  local base
  for base in "${unit_basenames[@]}"; do
    [ -z "$base" ] && continue
    local path="$qdir/$base"
    if [ -f "$path" ]; then
      unit_files+=("$path")
    else
      missing+=("$base")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    tgdb_err "找不到完整的 $display_name Quadlet 紀錄（缺少：${missing[*]}）：$name"
    ui_pause
    return 1
  fi

  local instance_dir="$TGDB_DIR/$name"
  mkdir -p "$instance_dir"

  if [ ${#mkdir_subdirs[@]} -gt 0 ]; then
    for base in "${mkdir_subdirs[@]}"; do
      [ -n "$base" ] && mkdir -p "$instance_dir/$base"
    done
  fi

  if [ -n "$chown_uidgid" ] && [ ${#chown_subdirs[@]} -gt 0 ]; then
    for base in "${chown_subdirs[@]}"; do
      [ -z "$base" ] && continue
      chown -R "$chown_uidgid" "$instance_dir/$base" 2>/dev/null || true
    done
  fi

  local -a cfgs=()
  if _app_fn_exists "$service" record_config_paths; then
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && [ -f "$line" ] && cfgs+=("$line")
    done < <(_app_invoke "$service" record_config_paths "$name" 2>/dev/null || true)
  fi

  if [ ${#cfgs[@]} -gt 0 ]; then
    if _app_fn_exists "$service" copy_config_to_instance; then
      local cfg
      for cfg in "${cfgs[@]}"; do
        _app_invoke "$service" copy_config_to_instance "$cfg" "$instance_dir" || true
      done
    else
      local cfg
      for cfg in "${cfgs[@]}"; do
        cp "$cfg" "$instance_dir/" 2>/dev/null || true
      done
    fi
  else
    if _app_fn_exists "$service" record_config_paths; then
      tgdb_warn "找不到設定檔紀錄（$display_name）：$name（若容器啟動失敗請先補齊必要環境變數）"
    fi
  fi

  if ! _install_quadlet_units_from_files "${unit_files[@]}"; then
    tgdb_err "從紀錄部署失敗：$name（單元啟用失敗）"
    ui_pause
    return 1
  fi
  _post_deploy_app "$service" "$name"
  echo "✅ 已從紀錄部署：$name"
  ui_pause
}

_app_systemd_restart_by_unit_filename() {
  local unit_filename="$1"
  [ -z "$unit_filename" ] && return 0

  local base="${unit_filename%.*}"
  local ext="${unit_filename##*.}"

  case "$ext" in
    container)
      _systemctl_user_try restart -- "$unit_filename" "$base.service" "container-$base.service" || true
      ;;
    pod)
      _systemctl_user_try restart -- "$unit_filename" "pod-$base.service" || true
      ;;
    *)
      _systemctl_user_try restart -- "$unit_filename" || true
      ;;
  esac
}

_app_systemd_disable_now_by_unit_filename() {
  local unit_filename="$1"
  [ -z "$unit_filename" ] && return 0

  local base="${unit_filename%.*}"
  local ext="${unit_filename##*.}"

  case "$ext" in
    container)
      _systemctl_user_try disable --now -- "$unit_filename" "$base.service" "container-$base.service" || true
      ;;
    pod)
      _systemctl_user_try disable --now -- "$unit_filename" "pod-$base.service" || true
      ;;
    *)
      _systemctl_user_try disable --now -- "$unit_filename" || true
      ;;
  esac
}

_app_restart_units_by_filenames() {
  if [ "$#" -le 0 ]; then
    return 0
  fi

  local unit
  for unit in "$@"; do
    _app_systemd_restart_by_unit_filename "$unit"
  done
}

_app_full_remove_units_by_filenames() {
  if [ "$#" -le 0 ]; then
    return 0
  fi

  local unit base

  for unit in "$@"; do
    case "$unit" in
      *.container) _app_systemd_disable_now_by_unit_filename "$unit" ;;
    esac
  done
  for unit in "$@"; do
    case "$unit" in
      *.pod) _app_systemd_disable_now_by_unit_filename "$unit" ;;
    esac
  done

  for unit in "$@"; do
    case "$unit" in
      *.container)
        base="${unit%.container}"
        podman rm -f "$base" 2>/dev/null || true
        ;;
    esac
  done
  for unit in "$@"; do
    case "$unit" in
      *.pod)
        base="${unit%.pod}"
        podman pod rm -f "$base" 2>/dev/null || true
        ;;
    esac
  done

  local user_units_dir
  user_units_dir="$(rm_user_units_dir)"
  for unit in "$@"; do
    rm -f "$user_units_dir/$unit" 2>/dev/null || true
  done
}

_app_try_delete_path() {
  local delete_path="$1" method="${2:-unshare}"

  case "$method" in
    rm)
      if ! rm -rf "$delete_path" 2>/dev/null; then
        if [ -d "$delete_path" ]; then
          tgdb_warn "無法刪除實例資料夾：$delete_path"
          tgdb_warn "可能因權限不足（例如容器以 root 建立檔案），請使用 sudo 或 root 手動清理。"
          return 1
        fi
      fi
      return 0
      ;;
    unshare|*)
      if ! podman unshare rm -rf "$delete_path" 2>/dev/null; then
        if [ -d "$delete_path" ]; then
          tgdb_warn "無法刪除實例資料夾：$delete_path"
          tgdb_warn "可能因權限不足（例如容器以 root 建立檔案），請使用 sudo 或 root 手動清理。"
          return 1
        fi
      fi
      return 0
      ;;
  esac
}

_app_record_files() {
  local service="$1" name="$2"
  _app_invoke "$service" record_files "$name"
}

_list_record_names() {
  local service="$1"
  local cdir qdir
  cdir=$(_service_config_dir "$service")
  qdir=$(_service_quadlet_dir "$service")
  local names=()
  if [ -d "$cdir" ]; then
    while IFS= read -r -d $'\0' f; do
      local b="${f##*/}"
      [ "$b" = "default.conf" ] && continue
      local n="${b%.*}"
      # AppSpec 多設定檔紀錄：檔名為 ${name}__${dest_basename}
      # 這裡只取 name 部分，避免記錄清單出現多筆同名實例。
      if [[ "$n" == *__* ]]; then
        n="${n%%__*}"
      fi
      if _app_is_aux_instance_name "$service" "$n"; then
        continue
      fi
      names+=("$n")
    done < <(find "$cdir" -maxdepth 1 -type f \( -name "*.json" -o -name "*.toml" -o -name "*.conf" -o -name "*.env" \) -print0 2>/dev/null)
  fi
  if [ -d "$qdir" ]; then
    while IFS= read -r -d $'\0' f; do
      local b="${f##*/}"
      local n="${b%.container}"
      if _app_is_aux_instance_name "$service" "$n"; then
        continue
      fi
      names+=("$n")
    done < <(find "$qdir" -maxdepth 1 -type f -name "*.container" -print0 2>/dev/null)
    while IFS= read -r -d $'\0' f; do
      local b="${f##*/}"
      local n="${b%.pod}"
      if _app_is_aux_instance_name "$service" "$n"; then
        continue
      fi
      names+=("$n")
    done < <(find "$qdir" -maxdepth 1 -type f -name "*.pod" -print0 2>/dev/null)
  fi
  printf "%s\n" "${names[@]}" | sort -u
}

_select_record() {
  local service="$1"
  SELECTED_RECORD=""
  local arr=()
  while IFS= read -r n; do
    [ -n "$n" ] && arr+=("$n")
  done < <(_list_record_names "$service")
  if [ ${#arr[@]} -eq 0 ]; then
    echo "尚無 '$service' 紀錄，請先透過『快速部署』保存紀錄。"
    ui_pause
    return 1
  fi
  while true; do
    clear
    echo "=================================="
    echo "❖ 已保存的 $service 紀錄 ❖"
    echo "----------------------------------"
    local i=1
    for n in "${arr[@]}"; do
      echo "$i. $n"
      i=$((i + 1))
    done
    echo "----------------------------------"
    echo "0. 取消"
    echo "=================================="
    if ! ui_prompt_index choice "請輸入選擇 [0-${#arr[@]}]: " 1 "${#arr[@]}" "" 0; then
      return 1
    fi
    SELECTED_RECORD=${arr[$((choice - 1))]}
    return 0
  done
}

_quadlet_unit_subdir_for_type() {
  local t="$1"
  if declare -F rm_quadlet_subdir_by_ext >/dev/null 2>&1; then
    rm_quadlet_subdir_by_ext "$t"
    return $?
  fi
  case "$t" in
    container) echo "containers" ;;
    network) echo "networks" ;;
    volume) echo "volumes" ;;
    pod) echo "pods" ;;
    device) echo "devices" ;;
    *) return 1 ;;
  esac
}

_list_quadlet_unit_names() {
  local type="$1"
  local subdir d
  subdir=$(_quadlet_unit_subdir_for_type "$type") || return 0
  d="$(rm_persist_quadlet_subdir_dir "$subdir")"
  [ -d "$d" ] || return 0
  local names=()
  while IFS= read -r -d $'\0' f; do
    local b="${f##*/}"
    [[ "$b" != *."$type" ]] && continue
    names+=("${b%.*}")
  done < <(find "$d" -maxdepth 1 -type f -name "*.$type" -print0 2>/dev/null)
  printf "%s\n" "${names[@]}" | sort -u
}

_select_quadlet_unit_type() {
  SELECTED_QUADLET_TYPE=""
  while true; do
    clear
    echo "=================================="
    echo "❖ 選擇 Quadlet 單元種類 ❖"
    echo "=================================="
    echo "1) container"
    echo "2) network"
    echo "3) volume"
    echo "4) pod"
    echo "5) device"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-5]: " c
    case "$c" in
      1) SELECTED_QUADLET_TYPE="container"; return 0 ;;
      2) SELECTED_QUADLET_TYPE="network"; return 0 ;;
      3) SELECTED_QUADLET_TYPE="volume"; return 0 ;;
      4) SELECTED_QUADLET_TYPE="pod"; return 0 ;;
      5) SELECTED_QUADLET_TYPE="device"; return 0 ;;
      0) return 1 ;;
      *) echo "無效選項"; sleep 1 ;;
    esac
  done
}

_select_quadlet_unit_record() {
  local type="$1"
  SELECTED_QUADLET_NAME=""
  local arr=()
  while IFS= read -r n; do
    [ -n "$n" ] && arr+=("$n")
  done < <(_list_quadlet_unit_names "$type")
  if [ ${#arr[@]} -eq 0 ]; then
    local sub
    sub=$(_quadlet_unit_subdir_for_type "$type") || sub="$type"
    echo "目前 config/quadlet/$sub 尚無任何 '$type' 單元紀錄。"
    ui_pause
    return 1
  fi
  while true; do
    clear
    echo "=================================="
    echo "❖ config/quadlet 自訂 $type 單元 ❖"
    echo "----------------------------------"
    local i=1
    for n in "${arr[@]}"; do
      echo "$i. $n"
      i=$((i + 1))
    done
    echo "----------------------------------"
    echo "0. 取消"
    echo "=================================="
    if ! ui_prompt_index choice "請輸入選擇 [0-${#arr[@]}]: " 1 "${#arr[@]}" "" 0; then
      return 1
    fi
    SELECTED_QUADLET_NAME=${arr[$((choice - 1))]}
    return 0
  done
}

_deploy_from_config_quadlet_unit() {
  local type="$1"
  _ensure_user_units_dir
  if ! _select_quadlet_unit_record "$type"; then
    return 1
  fi
  local name="$SELECTED_QUADLET_NAME"
  local sub d quad
  sub=$(_quadlet_unit_subdir_for_type "$type") || return 1
  d="$(rm_persist_quadlet_subdir_dir "$sub")"
  quad="$d/$name.$type"
  if [ ! -f "$quad" ]; then
    tgdb_err "找不到 Quadlet 單元：$quad"
    ui_pause
    return 1
  fi

  case "$type" in
    container)
      _install_unit_and_enable "$name" "$(cat "$quad")"
      ;;
    *)
      local dest
      dest="$(rm_user_unit_path "$name.$type")"
      _write_file "$dest" "$(cat "$quad")"
      _systemctl_user_try daemon-reload || true
      ;;
  esac

  echo "✅ 已從 config/quadlet 部署：$name.$type"
  ui_pause
}

_edit_config_quadlet_unit() {
  local type="$1"
  if ! _select_quadlet_unit_record "$type"; then
    return 1
  fi
  local name="$SELECTED_QUADLET_NAME"
  local sub d quad
  sub=$(_quadlet_unit_subdir_for_type "$type") || return 1
  d="$(rm_persist_quadlet_subdir_dir "$sub")"
  quad="$d/$name.$type"
  if [ ! -f "$quad" ]; then
    tgdb_err "找不到可編輯的 Quadlet 單元：$quad"
    ui_pause
    return 1
  fi
  if ! ensure_editor; then
    tgdb_err "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。"
    ui_pause
    return 1
  fi
  "$EDITOR" "$quad"
  echo "✅ 已完成編輯：config/quadlet/$sub/$name.$type"
  ui_pause
}

_delete_config_quadlet_unit() {
  local type="$1"
  if ! _select_quadlet_unit_record "$type"; then
    return 1
  fi
  local name="$SELECTED_QUADLET_NAME"
  local sub d quad
  sub=$(_quadlet_unit_subdir_for_type "$type") || return 1
  d="$(rm_persist_quadlet_subdir_dir "$sub")"
  quad="$d/$name.$type"
  if [ ! -f "$quad" ]; then
    tgdb_err "找不到可刪除的 Quadlet 單元：$quad"
    ui_pause
    return 1
  fi
  echo "您即將刪除紀錄：config/quadlet/$sub/$name.$type"
  if ui_confirm_yn "確認刪除？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    rm -f "$quad"
    echo "✅ 已刪除：config/quadlet/$sub/$name.$type"
  else
    echo "已取消刪除"
  fi
  ui_pause
}

config_quadlet_custom_menu() {
  while true; do
    if ! _select_quadlet_unit_type; then
      return
    fi
    local utype="$SELECTED_QUADLET_TYPE"
    while true; do
      clear
      echo "=================================="
      echo "❖ 自訂義程式管理（$utype 單元）❖"
      echo "=================================="
      echo "1. 從紀錄部署"
      echo "2. 編輯紀錄"
      echo "3. 刪除紀錄"
      echo "----------------------------------"
      echo "0. 返回上一層"
      echo "=================================="
      read -r -e -p "請輸入選擇 [0-3]: " c
      case "$c" in
        1) _deploy_from_config_quadlet_unit "$utype" || true ;;
        2) _edit_config_quadlet_unit "$utype" || true ;;
        3) _delete_config_quadlet_unit "$utype" || true ;;
        0) break ;;
        *) echo "無效選項"; sleep 1 ;;
      esac
    done
  done
}

deploy_from_record_p() {
  local service="$1" name="$2"
  _app_invoke "$service" deploy_from_record "$name"
}

edit_record_cli() {
  local service="$1" name="$2"
  if [ -z "${service:-}" ] || [ -z "${name:-}" ]; then
    tgdb_fail "用法：edit_record_cli <service> <name>" 2 || return $?
  fi
  if [[ "$name" == *"/"* ]] || [[ "$name" == *".."* ]]; then
    tgdb_fail "名稱不合法：$name" 2 || return $?
  fi

  local files=() p
  while IFS= read -r p; do
    [ -n "$p" ] && [ -f "$p" ] && files+=("$p")
  done < <(_app_record_files "$service" "$name")

  if [ ${#files[@]} -eq 0 ]; then
    tgdb_fail "找不到可編輯的紀錄檔：$service/$name" 1 || return $?
  fi

  if ! ensure_editor; then
    tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || return $?
  fi
  "$EDITOR" "${files[@]}"

  echo "✅ 已完成編輯：$service/$name"
}

delete_record_cli() {
  local service="$1" name="$2"
  if [ -z "${service:-}" ] || [ -z "${name:-}" ]; then
    tgdb_fail "用法：delete_record_cli <service> <name>" 2 || return $?
  fi
  if [[ "$name" == *"/"* ]] || [[ "$name" == *".."* ]]; then
    tgdb_fail "名稱不合法：$name" 2 || return $?
  fi

  local files=() p
  while IFS= read -r p; do
    [ -n "$p" ] && [ -f "$p" ] && files+=("$p")
  done < <(_app_record_files "$service" "$name")

  if [ ${#files[@]} -eq 0 ]; then
    tgdb_fail "找不到可刪除的紀錄檔：$service/$name" 1 || return $?
  fi

  local f
  for f in "${files[@]}"; do
    rm -f "$f"
  done
  echo "✅ 已刪除紀錄：$service/$name"
}

edit_record_p() {
  local service="$1"
  if ! _select_record "$service"; then
    return 1
  fi
  local name="$SELECTED_RECORD"

  local files=() p
  while IFS= read -r p; do
    [ -n "$p" ] && [ -f "$p" ] && files+=("$p")
  done < <(_app_record_files "$service" "$name")

  if [ ${#files[@]} -eq 0 ]; then
    tgdb_err "找不到可編輯的紀錄檔"
    ui_pause
    return 1
  fi

  if ! ensure_editor; then
    tgdb_err "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。"
    ui_pause
    return 1
  fi
  "$EDITOR" "${files[@]}"

  echo "✅ 已完成編輯：$service/$name"
  ui_pause
}

delete_record_p() {
  local service="$1"
  if ! _select_record "$service"; then
    return 1
  fi
  local name="$SELECTED_RECORD"

  local files=()
  local p
  while IFS= read -r p; do
    [ -n "$p" ] && [ -f "$p" ] && files+=("$p")
  done < <(_app_record_files "$service" "$name")

  if [ ${#files[@]} -eq 0 ]; then
    tgdb_err "找不到可刪除的紀錄檔"
    ui_pause
    return 1
  fi

  echo "您即將刪除紀錄：$service/$name"
  if ui_confirm_yn "確認刪除？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    local f
    for f in "${files[@]}"; do
      rm -f "$f"
    done
    echo "✅ 已刪除：$service/$name"
  else
    echo "已取消刪除"
  fi
  ui_pause
}

config_p_deployment_flow() {
  local service="${1:-}"
  if [ -z "$service" ]; then
    local -a available_services=()
    local s
    while IFS= read -r s; do
      [ -n "$s" ] && available_services+=("$s")
    done < <(_apps_list_services)

    if [ ${#available_services[@]} -eq 0 ]; then
      tgdb_err "目前找不到任何可用的 app 規格（config/*/app.spec）。"
      ui_pause
      return 1
    fi

    while true; do
      clear
      echo "=================================="
      echo "❖ 客製化部署（Quadlet）選擇服務 ❖"
      echo "=================================="
      _apps_render_menu 3 1 "${available_services[@]}"
      echo "----------------------------------"
      echo "0. 取消"
      echo "=================================="
      if ! ui_prompt_index sc "請輸入選擇 [0-${#available_services[@]}]: " 1 "${#available_services[@]}" "" 0; then
        return 1
      fi
      service=${available_services[$((sc - 1))]}
      break
    done
  fi

  local has_any=false tmp
  tmp=$(_list_record_names "$service")
  [ -n "$tmp" ] && has_any=true
  if [ "$has_any" = false ]; then
    echo "目前尚無任何 '$service' 的紀錄，請先於應用管理中執行『快速部署』。"
    ui_pause
    return 1
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ $service 配置管理（Quadlet）❖"
    echo "=================================="
    echo "現有紀錄（輸入編號直接部屬）："
    local arr=() n
    while IFS= read -r n; do
      [ -n "$n" ] && arr+=("$n")
    done < <(_list_record_names "$service")
    local i
    for i in "${!arr[@]}"; do
      printf "  %d. %s\n" "$((i + 1))" "${arr[$i]}"
    done
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    ui_prompt_index choice "請輸入紀錄編號以部屬 [0-${#arr[@]}]: " 0 "${#arr[@]}" "" "" || return $?
    if [ "$choice" -eq 0 ]; then
      return 0
    fi
    local name="${arr[$((choice - 1))]}"
    deploy_from_record_p "$service" "$name"
  done
}
