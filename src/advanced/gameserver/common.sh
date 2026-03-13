#!/bin/bash

# Game Server：共用函式（驗證、路徑、實例發現、metadata）
# 注意：此檔案為 library，會被 source；請勿在此更改 shell options。

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_GAMESERVER_COMMON_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_GAMESERVER_COMMON_LOADED=1

GAMESERVER_UNIT_PREFIX="gameserver-"

_gameserver_shortname_url() {
  printf '%s\n' "https://github.com/GameServerManagers/LinuxGSM/blob/master/lgsm/data/serverlist.csv"
}

if [ -z "${SRC_ROOT:-}" ]; then
  SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

_gameserver_require_tty() {
  if ! ui_is_interactive; then
    tgdb_fail "Game Server 管理需要互動式終端（TTY）。" 2 || true
    return 2
  fi
  return 0
}

_gameserver_require_podman() {
  if command -v podman >/dev/null 2>&1; then
    return 0
  fi
  tgdb_fail "未偵測到 Podman，Game Server 需要 Podman + Quadlet。" 1 || true
  echo "請先到主選單：5. Podman 管理 → 安裝/更新 Podman"
  return 1
}

_gameserver_normalize_arch() {
  local raw="${1:-}"
  case "${raw,,}" in
    x86_64|amd64) printf '%s\n' "amd64" ;;
    aarch64|arm64) printf '%s\n' "arm64" ;;
    armv7l|armv7|armhf) printf '%s\n' "arm" ;;
    i386|i686|x86) printf '%s\n' "386" ;;
    *) printf '%s\n' "${raw,,}" ;;
  esac
}

_gameserver_host_arch() {
  local raw
  raw="$(uname -m 2>/dev/null || echo unknown)"
  _gameserver_normalize_arch "$raw"
}

_gameserver_require_supported_arch() {
  local host_arch
  host_arch="$(_gameserver_host_arch)"

  case "$host_arch" in
    amd64)
      return 0
      ;;
    arm|arm64)
      tgdb_fail "目前偵測主機架構：${host_arch}
Game Server 目前不支援 ARM（含 Oracle ARM）。
請改用 AMD64（x86_64）主機部署。" 1 || true
      return 1
      ;;
    *)
      tgdb_fail "目前偵測主機架構：${host_arch}
Game Server 目前僅支援 AMD64（x86_64）部署。" 1 || true
      return 1
      ;;
  esac
}

_gameserver_records_root_dir() {
  printf '%s\n' "$(rm_persist_config_dir)/gameserver"
}

_gameserver_records_instances_dir() {
  printf '%s\n' "$(_gameserver_records_root_dir)/instances"
}

_gameserver_records_quadlet_dir() {
  printf '%s\n' "$(_gameserver_records_root_dir)/quadlet"
}

_gameserver_record_env_path() {
  local unit_base="$1"
  printf '%s\n' "$(_gameserver_records_instances_dir)/${unit_base}.env"
}

_gameserver_record_quadlet_path() {
  local unit_base="$1"
  printf '%s\n' "$(_gameserver_records_quadlet_dir)/${unit_base}.container"
}

_gameserver_repo_quadlet_template() {
  printf '%s\n' "$CONFIG_DIR/gameserver/quadlet/default.container"
}

_gameserver_instance_dir() {
  local unit_base="$1"
  printf '%s\n' "$TGDB_DIR/$unit_base"
}

_gameserver_instance_meta_path() {
  local unit_base="$1"
  printf '%s\n' "$(_gameserver_instance_dir "$unit_base")/.gameserver.meta"
}

_gameserver_unit_path() {
  local unit_base="$1"
  rm_user_unit_path "${unit_base}.container"
}

_gameserver_trim_ws() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

_gameserver_is_valid_shortname() {
  local v="${1:-}"
  [[ "$v" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

_gameserver_is_valid_instance_name() {
  local v="${1:-}"
  [[ "$v" =~ ^[a-z0-9][a-z0-9._-]*$ ]]
}

_gameserver_is_valid_unit_base() {
  local v="${1:-}"
  [[ "$v" =~ ^gameserver-[a-z0-9][a-z0-9._-]*$ ]]
}

_gameserver_unit_base_from_instance_name() {
  local instance_name="$1"
  printf '%s\n' "${GAMESERVER_UNIT_PREFIX}${instance_name}"
}

_gameserver_instance_name_from_unit_base() {
  local unit_base="$1"
  if [[ "$unit_base" == ${GAMESERVER_UNIT_PREFIX}* ]]; then
    printf '%s\n' "${unit_base#"$GAMESERVER_UNIT_PREFIX"}"
  else
    printf '%s\n' "$unit_base"
  fi
}

_gameserver_container_name_from_unit_base() {
  local unit_base="$1"
  printf '%s\n' "$unit_base"
}

_gameserver_now_iso8601() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S"
}

_gameserver_env_get() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  [ -n "$key" ] || return 1
  awk -F= -v k="$key" '
    $1 == k {
      $1 = ""
      sub(/^=/, "", $0)
      print $0
      exit
    }
  ' "$file" 2>/dev/null
}

_gameserver_ensure_records_layout() {
  mkdir -p "$(_gameserver_records_instances_dir)" "$(_gameserver_records_quadlet_dir)"
}

_gameserver_write_instance_metadata() {
  local instance_name="$1"
  local unit_base="$2"
  local container_name="$3"
  local shortname="$4"
  local image="$5"
  local instance_dir="$6"
  local volume_dir="$7"

  _gameserver_ensure_records_layout
  mkdir -p "$instance_dir"

  local now
  now="$(_gameserver_now_iso8601)"

  local content=""
  content+="INSTANCE_NAME=${instance_name}"$'\n'
  content+="UNIT_BASE=${unit_base}"$'\n'
  content+="CONTAINER_NAME=${container_name}"$'\n'
  content+="SHORTNAME=${shortname}"$'\n'
  content+="IMAGE=${image}"$'\n'
  content+="INSTANCE_DIR=${instance_dir}"$'\n'
  content+="VOLUME_DIR=${volume_dir}"$'\n'
  content+="CREATED_AT=${now}"$'\n'

  _write_file "$(_gameserver_instance_meta_path "$unit_base")" "$content"
  _write_file "$(_gameserver_record_env_path "$unit_base")" "$content"
  chmod 600 "$(_gameserver_instance_meta_path "$unit_base")" "$(_gameserver_record_env_path "$unit_base")" 2>/dev/null || true
}

_gameserver_write_record_quadlet() {
  local unit_base="$1" unit_content="$2"
  _gameserver_ensure_records_layout
  _write_file "$(_gameserver_record_quadlet_path "$unit_base")" "$unit_content"
}

_gameserver_remove_records() {
  local unit_base="$1"
  rm -f "$(_gameserver_record_env_path "$unit_base")" "$(_gameserver_record_quadlet_path "$unit_base")" 2>/dev/null || true
}

_gameserver_add_unit_base_unique() {
  local unit_base="$1"
  local -n out_ref="$2"
  local -n seen_ref="$3"

  [ -n "$unit_base" ] || return 0
  _gameserver_is_valid_unit_base "$unit_base" || return 0

  if [ -n "${seen_ref[$unit_base]+x}" ]; then
    return 0
  fi

  seen_ref["$unit_base"]=1
  out_ref+=("$unit_base")
  return 0
}

_gameserver_list_unit_bases() {
  local -a found=()
  # shellcheck disable=SC2034  # 由 nameref 間接使用
  local -A seen=()
  local f b unit_base

  local records_dir
  records_dir="$(_gameserver_records_instances_dir)"
  if [ -d "$records_dir" ]; then
    while IFS= read -r -d $'\0' f; do
      b="${f##*/}"
      unit_base="${b%.env}"
      _gameserver_add_unit_base_unique "$unit_base" found seen || true
    done < <(find "$records_dir" -maxdepth 1 -type f -name "${GAMESERVER_UNIT_PREFIX}*.env" -print0 2>/dev/null)
  fi

  local units_dir
  units_dir="$(rm_user_units_dir)"
  if [ -d "$units_dir" ]; then
    while IFS= read -r -d $'\0' f; do
      b="${f##*/}"
      unit_base="${b%.container}"
      _gameserver_add_unit_base_unique "$unit_base" found seen || true
    done < <(find "$units_dir" -maxdepth 1 -type f -name "${GAMESERVER_UNIT_PREFIX}*.container" -print0 2>/dev/null)
  fi

  if [ ${#found[@]} -eq 0 ]; then
    return 0
  fi

  printf '%s\n' "${found[@]}" | LC_ALL=C sort -u
}

_gameserver_instance_exists() {
  local unit_base="$1"
  [ -n "$unit_base" ] || return 1

  [ -f "$(_gameserver_record_env_path "$unit_base")" ] && return 0
  [ -f "$(_gameserver_unit_path "$unit_base")" ] && return 0
  [ -d "$(_gameserver_instance_dir "$unit_base")" ] && return 0

  return 1
}

_gameserver_next_default_instance_name() {
  local shortname="$1"
  local i=1
  local candidate unit_base
  while true; do
    candidate="${shortname}${i}"
    unit_base="$(_gameserver_unit_base_from_instance_name "$candidate")"
    if ! _gameserver_instance_exists "$unit_base"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    i=$((i + 1))
  done
}

_gameserver_shortname_from_image() {
  local image="$1"
  local tag="${image##*:}"
  if _gameserver_is_valid_shortname "$tag"; then
    printf '%s\n' "$tag"
    return 0
  fi
  return 1
}

_gameserver_read_image_from_unit_file() {
  local unit_base="$1"
  local unit_file
  unit_file="$(_gameserver_unit_path "$unit_base")"
  [ -f "$unit_file" ] || return 1

  awk -F= '
    /^Image=/ {
      $1=""
      sub(/^=/, "", $0)
      print $0
      exit
    }
  ' "$unit_file" 2>/dev/null
}

_gameserver_read_data_volume_from_unit_file() {
  local unit_base="$1"
  local unit_file
  unit_file="$(_gameserver_unit_path "$unit_base")"
  [ -f "$unit_file" ] || return 1

  awk -F= '
    /^Volume=/ {
      $1 = ""
      sub(/^=/, "", $0)
      n = split($0, part, ":")
      if (n >= 2 && part[2] == "/data") {
        print part[1]
        exit
      }
    }
  ' "$unit_file" 2>/dev/null
}

_gameserver_image_of_unit() {
  local unit_base="$1"
  local image=""
  image="$(_gameserver_env_get "$(_gameserver_record_env_path "$unit_base")" "IMAGE" 2>/dev/null || true)"
  if [ -n "$image" ]; then
    printf '%s\n' "$image"
    return 0
  fi

  image="$(_gameserver_env_get "$(_gameserver_instance_meta_path "$unit_base")" "IMAGE" 2>/dev/null || true)"
  if [ -n "$image" ]; then
    printf '%s\n' "$image"
    return 0
  fi

  image="$(_gameserver_read_image_from_unit_file "$unit_base" 2>/dev/null || true)"
  if [ -n "$image" ]; then
    printf '%s\n' "$image"
    return 0
  fi

  return 1
}

_gameserver_volume_dir_of_unit() {
  local unit_base="$1"
  local volume_dir=""

  volume_dir="$(_gameserver_env_get "$(_gameserver_record_env_path "$unit_base")" "VOLUME_DIR" 2>/dev/null || true)"
  volume_dir="$(_gameserver_trim_ws "$volume_dir")"
  if [ -n "$volume_dir" ]; then
    printf '%s\n' "$volume_dir"
    return 0
  fi

  volume_dir="$(_gameserver_env_get "$(_gameserver_instance_meta_path "$unit_base")" "VOLUME_DIR" 2>/dev/null || true)"
  volume_dir="$(_gameserver_trim_ws "$volume_dir")"
  if [ -n "$volume_dir" ]; then
    printf '%s\n' "$volume_dir"
    return 0
  fi

  volume_dir="$(_gameserver_read_data_volume_from_unit_file "$unit_base" 2>/dev/null || true)"
  volume_dir="$(_gameserver_trim_ws "$volume_dir")"
  if [ -n "$volume_dir" ]; then
    printf '%s\n' "$volume_dir"
    return 0
  fi

  return 1
}

_gameserver_shortname_of_unit() {
  local unit_base="$1"
  local shortname=""
  shortname="$(_gameserver_env_get "$(_gameserver_record_env_path "$unit_base")" "SHORTNAME" 2>/dev/null || true)"
  if _gameserver_is_valid_shortname "$shortname"; then
    printf '%s\n' "$shortname"
    return 0
  fi

  shortname="$(_gameserver_env_get "$(_gameserver_instance_meta_path "$unit_base")" "SHORTNAME" 2>/dev/null || true)"
  if _gameserver_is_valid_shortname "$shortname"; then
    printf '%s\n' "$shortname"
    return 0
  fi

  local image=""
  image="$(_gameserver_image_of_unit "$unit_base" 2>/dev/null || true)"
  shortname="$(_gameserver_shortname_from_image "$image" 2>/dev/null || true)"
  if _gameserver_is_valid_shortname "$shortname"; then
    printf '%s\n' "$shortname"
    return 0
  fi

  return 1
}

_gameserver_unit_status() {
  local unit_base="$1"

  if command -v systemctl >/dev/null 2>&1; then
    local -a units=(
      "container-${unit_base}.service"
      "${unit_base}.service"
      "${unit_base}.container"
    )
    local u
    for u in "${units[@]}"; do
      if systemctl --user is-active --quiet "$u" 2>/dev/null; then
        printf '%s\n' "running"
        return 0
      fi
    done
    for u in "${units[@]}"; do
      if systemctl --user is-failed --quiet "$u" 2>/dev/null; then
        printf '%s\n' "failed"
        return 0
      fi
    done
  fi

  if command -v podman >/dev/null 2>&1; then
    if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$unit_base"; then
      printf '%s\n' "running"
      return 0
    fi
    if podman ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$unit_base"; then
      printf '%s\n' "stopped"
      return 0
    fi
  fi

  printf '%s\n' "unknown"
  return 0
}

_gameserver_status_text() {
  local s="$1"
  case "$s" in
    running) printf '%s\n' "運行中" ;;
    failed) printf '%s\n' "失敗" ;;
    stopped) printf '%s\n' "已停止" ;;
    *) printf '%s\n' "未知" ;;
  esac
}

_gameserver_select_unit_base() {
  local out_var="$1"
  local title="${2:-請選擇伺服器實例}"
  local -a units=()
  local u

  while IFS= read -r u; do
    [ -n "$u" ] && units+=("$u")
  done < <(_gameserver_list_unit_bases)

  if [ ${#units[@]} -eq 0 ]; then
    tgdb_warn "目前沒有任何 Game Server 實例。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ $title ❖"
    echo "=================================="
    local i=1
    for u in "${units[@]}"; do
      local instance_name shortname status
      instance_name="$(_gameserver_instance_name_from_unit_base "$u")"
      shortname="$(_gameserver_shortname_of_unit "$u" 2>/dev/null || echo "未知")"
      status="$(_gameserver_status_text "$(_gameserver_unit_status "$u")")"
      printf "%2d. %-20s shortname=%-12s 狀態=%s\n" "$i" "$instance_name" "$shortname" "$status"
      i=$((i + 1))
    done
    echo "----------------------------------"
    echo "0. 取消"
    echo "=================================="

    local idx=""
    if ! ui_prompt_index idx "請輸入選擇 [0-${#units[@]}]: " 1 "${#units[@]}" "" 0; then
      return 1
    fi
    printf -v "$out_var" '%s' "${units[$((idx - 1))]}"
    return 0
  done
}

_gameserver_ensure_podman_helpers() {
  if declare -F _unit_try_enable_now >/dev/null 2>&1 && \
    declare -F _unit_try_stop >/dev/null 2>&1 && \
    declare -F _unit_try_restart >/dev/null 2>&1 && \
    declare -F _remove_quadlet_unit >/dev/null 2>&1; then
    return 0
  fi

  local podman_module="$SRC_ROOT/podman.sh"
  if [ ! -f "$podman_module" ]; then
    tgdb_fail "找不到 Podman 模組：$podman_module" 1 || true
    return 1
  fi

  # shellcheck source=src/podman.sh
  source "$podman_module"

  if declare -F _unit_try_enable_now >/dev/null 2>&1 && \
    declare -F _unit_try_stop >/dev/null 2>&1 && \
    declare -F _unit_try_restart >/dev/null 2>&1 && \
    declare -F _remove_quadlet_unit >/dev/null 2>&1; then
    return 0
  fi

  tgdb_fail "載入 Podman helper 失敗，缺少必要函式。" 1 || true
  return 1
}
