#!/bin/bash

# Quadlet 共用輔助模組

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_CORE_QUADLET_COMMON_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_QUADLET_COMMON_LOADED=1

# 載入共用工具（tgdb_warn/tgdb_fail 等），避免各模組錯誤輸出不一致
# shellcheck source=src/core/bootstrap.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap.sh"

_esc() {
  printf '%s' "$1" | sed -e 's/[\\/&|]/\\&/g'
}

tgdb_normalize_deploy_mode() {
  local mode="${1:-rootless}"
  case "${mode,,}" in
    rootful|system) printf '%s\n' "rootful" ;;
    rootless|user|"") printf '%s\n' "rootless" ;;
    *) return 1 ;;
  esac
}

tgdb_scope_for_deploy_mode() {
  local mode
  mode="$(tgdb_normalize_deploy_mode "${1:-rootless}")" || return 1
  case "$mode" in
    rootful) printf '%s\n' "system" ;;
    rootless) printf '%s\n' "user" ;;
  esac
}

tgdb_normalize_scope() {
  local scope="${1:-user}"
  case "${scope,,}" in
    system|rootful) printf '%s\n' "system" ;;
    user|rootless|"") printf '%s\n' "user" ;;
    *) return 1 ;;
  esac
}

tgdb_active_deploy_mode() {
  local mode="${TGDB_APPS_ACTIVE_DEPLOY_MODE:-rootless}"
  tgdb_normalize_deploy_mode "$mode" 2>/dev/null || printf '%s\n' "rootless"
}

tgdb_active_scope() {
  local scope="${TGDB_APPS_ACTIVE_SCOPE:-}"
  if [ -n "$scope" ]; then
    tgdb_normalize_scope "$scope" 2>/dev/null || printf '%s\n' "user"
    return 0
  fi
  tgdb_scope_for_deploy_mode "$(tgdb_active_deploy_mode)" 2>/dev/null || printf '%s\n' "user"
}

tgdb_scope_label() {
  local scope
  scope="$(tgdb_normalize_scope "${1:-user}")" || return 1
  case "$scope" in
    system) printf '%s\n' "systemd system" ;;
    user) printf '%s\n' "systemd --user" ;;
  esac
}

tgdb_podman() {
  command -v podman >/dev/null 2>&1 || return 127

  local mode
  mode="$(tgdb_active_deploy_mode)"
  if [ "$mode" = "rootful" ]; then
    _tgdb_run_privileged podman "$@"
    return $?
  fi

  podman "$@"
}

tgdb_systemctl_try() {
  local scope="${1:-user}"
  shift || true

  scope="$(tgdb_normalize_scope "$scope")" || return 1
  command -v systemctl >/dev/null 2>&1 || return 1

  local want_no_block=0
  local -a args=()
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--" ]; then
      shift
      break
    fi
    if [ "$1" = "--no-block" ]; then
      want_no_block=1
      shift
      continue
    fi
    args+=("$1")
    shift
  done

  local -a cmd=()
  case "$scope" in
    system)
      if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
        cmd=(systemctl)
      elif command -v sudo >/dev/null 2>&1; then
        cmd=(sudo systemctl)
      else
        return 1
      fi
      ;;
    *)
      cmd=(systemctl --user)
      ;;
  esac
  if [ "$want_no_block" -eq 1 ]; then
    # systemctl 的全域參數（例如：--no-block）放在命令（start/restart/enable...）之前才最保險。
    cmd+=(--no-block)
  fi

  # 無 unit 的指令（例如：daemon-reload / list-timers --all / reset-failed）
  if [ "$#" -le 0 ]; then
    "${cmd[@]}" "${args[@]}" 2>/dev/null
    return $?
  fi

  local unit
  for unit in "$@"; do
    [ -z "$unit" ] && continue
    "${cmd[@]}" "${args[@]}" "$unit" 2>/dev/null && return 0
  done
  return 1
}

_systemctl_user_try() {
  tgdb_systemctl_try "$(tgdb_active_scope)" "$@"
}

_quadlet_user_units_dir() {
  if declare -F rm_quadlet_root_dir_by_mode >/dev/null 2>&1; then
    rm_quadlet_root_dir_by_mode "$(tgdb_active_deploy_mode)"
    return 0
  fi

  local scope
  scope="$(tgdb_active_scope)"
  if [ "$scope" = "system" ]; then
    printf '%s\n' "/etc/containers/systemd"
    return 0
  fi
  printf '%s\n' "${USER_UNITS_DIR:-$HOME/.config/containers/systemd}"
}

_ensure_user_units_dir() {
  local dir
  dir="$(_quadlet_user_units_dir)"
  if mkdir -p "$dir" 2>/dev/null; then
    return 0
  fi
  _tgdb_run_privileged mkdir -p "$dir"
}

_write_file() {
  local path="$1"
  shift
  local dir
  dir="$(dirname "$path")"
  if [ "$(tgdb_active_scope)" = "system" ]; then
    _tgdb_run_privileged mkdir -p "$dir" || return 1
    printf '%s' "$*" | _tgdb_run_privileged tee "$path" >/dev/null
    return $?
  fi
  if mkdir -p "$dir" 2>/dev/null && printf '%s' "$*" >"$path" 2>/dev/null; then
    return 0
  fi
  _tgdb_run_privileged mkdir -p "$dir" || return 1
  printf '%s' "$*" | _tgdb_run_privileged tee "$path" >/dev/null
}

_quadlet_runtime_unit_path() {
  local unit_filename="$1" service="${2:-}"
  if [ -n "$service" ] && declare -F rm_runtime_quadlet_unit_path_by_mode >/dev/null 2>&1; then
    rm_runtime_quadlet_unit_path_by_mode "$service" "$unit_filename" "$(tgdb_active_deploy_mode)"
    return 0
  fi
  if declare -F rm_tgdb_runtime_quadlet_root_dir_by_mode >/dev/null 2>&1; then
    printf '%s\n' "$(rm_tgdb_runtime_quadlet_root_dir_by_mode "$(tgdb_active_deploy_mode)")/$unit_filename"
    return 0
  fi
  printf '%s\n' "$(_quadlet_user_units_dir)/$unit_filename"
}

_quadlet_runtime_or_legacy_unit_path() {
  local unit_filename="$1" service="${2:-}"
  if [ -n "$service" ] && declare -F rm_runtime_or_legacy_quadlet_unit_path_by_mode >/dev/null 2>&1; then
    rm_runtime_or_legacy_quadlet_unit_path_by_mode "$service" "$unit_filename" "$(tgdb_active_deploy_mode)"
    return 0
  fi

  local runtime_path legacy_path
  runtime_path="$(_quadlet_runtime_unit_path "$unit_filename" "$service")"
  if [ -n "$runtime_path" ] && [ -e "$runtime_path" ]; then
    printf '%s\n' "$runtime_path"
    return 0
  fi

  if declare -F rm_legacy_quadlet_unit_path_by_mode >/dev/null 2>&1; then
    legacy_path="$(rm_legacy_quadlet_unit_path_by_mode "$unit_filename" "$(tgdb_active_deploy_mode)" 2>/dev/null || true)"
    if [ -n "$legacy_path" ] && [ -e "$legacy_path" ]; then
      printf '%s\n' "$legacy_path"
      return 0
    fi
  fi

  printf '%s\n' "$runtime_path"
}

_quadlet_runtime_unit_with_markers() {
  local unit_content="$1" service="${2:-}" instance="${3:-}"
  if [ -z "$service" ]; then
    printf '%s' "$unit_content"
    return 0
  fi

  local cleaned
  cleaned="$(printf '%s' "$unit_content" | awk '
    !/^[[:space:]]*# *TGDB-(Managed|Service|Instance|Deploy-Mode):/
  ')"

  printf '# TGDB-Managed: 1\n'
  printf '# TGDB-Service: %s\n' "$service"
  [ -n "$instance" ] && printf '# TGDB-Instance: %s\n' "$instance"
  printf '# TGDB-Deploy-Mode: %s\n' "$(tgdb_active_deploy_mode)"
  printf '%s' "$cleaned"
}

_quadlet_extract_images() {
  local unit_content="$1"
  printf '%s\n' "$unit_content" | awk '
    /^[[:space:]]*Image[[:space:]]*=/ {
      line=$0
      sub(/^[[:space:]]*Image[[:space:]]*=/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^"|"$/, "", line)
      if (line != "") print line
    }
  ' | awk '!seen[$0]++'
}

_quadlet_extract_build_tags() {
  local unit_content="$1"
  printf '%s\n' "$unit_content" | awk '
    /^[[:space:]]*ImageTag[[:space:]]*=/ {
      line=$0
      sub(/^[[:space:]]*ImageTag[[:space:]]*=/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^"|"$/, "", line)
      if (line != "") print line
    }
  ' | awk '!seen[$0]++'
}

_quadlet_image_exists_locally() {
  local image_ref="$1"
  [ -n "${image_ref:-}" ] || return 1

  if ! command -v podman >/dev/null 2>&1; then
    return 1
  fi

  if tgdb_podman image exists --help >/dev/null 2>&1; then
    tgdb_podman image exists "$image_ref" >/dev/null 2>&1
    return $?
  fi

  tgdb_podman image inspect "$image_ref" >/dev/null 2>&1
}

_quadlet_build_file_can_skip() {
  local file="$1"
  [ -f "$file" ] || return 1
  [ "${TGDB_QUADLET_BUILD_FORCE:-0}" = "1" ] && return 1

  local unit_content
  unit_content="$(cat "$file" 2>/dev/null || true)"

  local has_tag=0 tag
  while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    has_tag=1
    if ! _quadlet_image_exists_locally "$tag"; then
      return 1
    fi
  done < <(_quadlet_extract_build_tags "$unit_content")

  [ "$has_tag" -eq 1 ]
}

_quadlet_follow_unit_logs_bg() {
  local unit_name="$1"
  local out_pid_var="${2:-}"
  [ -n "${unit_name:-}" ] || return 1
  [ -n "${out_pid_var:-}" ] || return 1
  command -v journalctl >/dev/null 2>&1 || return 1

  # shellcheck disable=SC2178 # nameref 回傳 PID（shellcheck 誤判）
  local -n out_pid_ref="$out_pid_var"
  out_pid_ref=""

  local scope
  scope="$(tgdb_active_scope)"

  if [ "$scope" = "system" ]; then
    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
      journalctl -f -n 20 -u "$unit_name" -o cat &
      # shellcheck disable=SC2034 # nameref 用於回傳 PID（shellcheck 誤判）
      out_pid_ref="$!"
      return 0
    fi
    if command -v sudo >/dev/null 2>&1; then
      sudo journalctl -f -n 20 -u "$unit_name" -o cat &
      # shellcheck disable=SC2034 # nameref 用於回傳 PID（shellcheck 誤判）
      out_pid_ref="$!"
      return 0
    fi
    return 1
  fi

  journalctl --user -f -n 20 -u "$unit_name" -o cat &
  # shellcheck disable=SC2034 # nameref 用於回傳 PID（shellcheck 誤判）
  out_pid_ref="$!"
  return 0
}

_quadlet_podman_pull_policy() {
  local policy="${TGDB_PODMAN_PULL_POLICY:-missing}"
  case "$policy" in
    always|missing|never)
      ;;
    *)
      tgdb_warn "TGDB_PODMAN_PULL_POLICY=$policy 無效，將改用 missing"
      policy="missing"
      ;;
  esac
  printf '%s\n' "$policy"
}

_quadlet_pull_images() {
  if [ "$#" -le 0 ]; then
    return 0
  fi

  if ! command -v podman >/dev/null 2>&1; then
    return 0
  fi

  local has_image_exists=0
  tgdb_podman image exists --help >/dev/null 2>&1 && has_image_exists=1

  local policy
  policy="$(_quadlet_podman_pull_policy)"
  if [ "$policy" = "never" ]; then
    return 0
  fi

  if [ "$policy" = "missing" ]; then
    echo "📥 正在檢查/拉取容器映像（僅缺少才拉取）..."
  else
    echo "📥 正在拉取容器映像（顯示下載進度）..."
  fi

  local img
  local failed=0
  local -a failed_images=()
  for img in "$@"; do
    [ -z "$img" ] && continue

    if [ "$policy" = "missing" ]; then
      if [ "$has_image_exists" -eq 1 ]; then
        tgdb_podman image exists "$img" >/dev/null 2>&1 && continue
      else
        tgdb_podman image inspect "$img" >/dev/null 2>&1 && continue
      fi
    fi

    echo "   - $img"
    if ! tgdb_podman pull "$img"; then
      # 拉取失敗時，若本機仍有既有映像可用，允許繼續（例如暫時性網路問題）。
      local exists_locally=1
      if [ "$has_image_exists" -eq 1 ]; then
        tgdb_podman image exists "$img" >/dev/null 2>&1 || exists_locally=0
      else
        tgdb_podman image inspect "$img" >/dev/null 2>&1 || exists_locally=0
      fi

      if [ "$exists_locally" -eq 1 ]; then
        tgdb_warn "拉取映像失敗：$img（將改用本機既有映像繼續）"
      else
        tgdb_err "拉取映像失敗且本機無可用映像：$img"
        failed=1
        failed_images+=("$img")
      fi
    fi
  done

  if [ "$failed" -ne 0 ]; then
    tgdb_fail "以下映像拉取失敗且本機無可用映像：${failed_images[*]}" 1 || return $?
    return 1
  fi

  return 0
}

_quadlet_pull_images_from_unit() {
  local unit_content="$1"

  if ! command -v podman >/dev/null 2>&1; then
    return 0
  fi

  local images=() image
  while IFS= read -r image; do
    [ -n "$image" ] && images+=("$image")
  done < <(_quadlet_extract_images "$unit_content")

  if [ ${#images[@]} -eq 0 ]; then
    return 0
  fi

  _quadlet_pull_images "${images[@]}"
}

_install_unit_and_enable() {
  local service=""
  local name="$1"
  shift || true

  if [ "$#" -gt 1 ]; then
    service="$name"
    name="$1"
    shift || true
  fi

  local unit_content="$*"
  local runtime_content
  runtime_content="$(_quadlet_runtime_unit_with_markers "$unit_content" "$service" "$name")"

  _quadlet_pull_images_from_unit "$runtime_content" || return $?
  echo "⏳ 正在套用佈署並啟動服務，請稍等..."

  if ! _ensure_user_units_dir; then
    tgdb_fail "無法建立 Quadlet 單元目錄：$(_quadlet_user_units_dir)" 1 || return $?
    return 1
  fi
  local unit_path
  unit_path="$(_quadlet_runtime_unit_path "$name.container" "$service")"
  if ! _write_file "$unit_path" "$runtime_content"; then
    tgdb_fail "寫入 Quadlet 單元失敗：$unit_path" 1 || return $?
    return 1
  fi
  if ! _systemctl_user_try daemon-reload; then
    tgdb_fail "無法執行 $(tgdb_scope_label "$(tgdb_active_scope)") daemon-reload，請確認對應 systemd/DBus 環境可用。" 1 || return $?
    return 1
  fi

  if _systemctl_user_try enable --now -- "$name.container" "$name.service" "container-$name.service" "$name.network"; then
    return 0
  fi

  if _systemctl_user_try start --no-block -- "$name.service" "container-$name.service"; then
    return 0
  fi

  tgdb_fail "無法啟用或啟動服務：$name（請檢查 $(tgdb_scope_label "$(tgdb_active_scope)") 與單元日誌）。" 1 || return $?
  return 1
}

_install_service_unit_and_enable() {
  local service="$1" name="$2"
  shift 2 || true
  _install_unit_and_enable "$service" "$name" "$@"
}

_quadlet_enable_now_by_filename() {
  local unit_filename="$1"
  local base="${unit_filename%.*}"
  local ext="${unit_filename##*.}"

  case "$ext" in
    container)
      if _systemctl_user_try enable --now -- "$unit_filename" "$base.service" "container-$base.service"; then
        return 0
      fi
      if _systemctl_user_try start --no-block -- "$base.service" "container-$base.service"; then
        return 0
      fi
      tgdb_err "無法啟用/啟動容器單元：$unit_filename"
      return 1
      ;;
    pod)
      # 兼容不同 Quadlet/Podman 版本的 pod service 命名：
      # - 新版常見：<name>-pod.service
      # - 舊版/其他來源：pod-<name>.service
      if _systemctl_user_try enable --now -- "$unit_filename" "$base-pod.service" "pod-$base.service" "podman-pod-$base.service"; then
        return 0
      fi
      if _systemctl_user_try start --no-block -- "$base-pod.service" "pod-$base.service" "podman-pod-$base.service"; then
        return 0
      fi
      tgdb_err "無法啟用/啟動 Pod 單元：$unit_filename"
      return 1
      ;;
    build)
      local follow_pid=""
      if [ "${TGDB_BUILD_SHOW_PROGRESS:-1}" = "1" ]; then
        _quadlet_follow_unit_logs_bg "$base-build.service" follow_pid 2>/dev/null || true
      fi
      if _systemctl_user_try start --wait -- "$unit_filename" "$base-build.service"; then
        if [ -n "$follow_pid" ]; then
          kill "$follow_pid" 2>/dev/null || true
          wait "$follow_pid" 2>/dev/null || true
        fi
        return 0
      fi
      if [ -n "$follow_pid" ]; then
        kill "$follow_pid" 2>/dev/null || true
        wait "$follow_pid" 2>/dev/null || true
      fi
      tgdb_err "無法完成建置單元：$unit_filename"
      return 1
      ;;
    *)
      if _systemctl_user_try enable --now -- "$unit_filename"; then
        return 0
      fi
      tgdb_err "無法啟用單元：$unit_filename"
      return 1
      ;;
  esac
}

_quadlet_enable_now_bulk_by_filenames() {
  if [ "$#" -le 0 ]; then
    return 0
  fi

  local has_build=0 unit
  for unit in "$@"; do
    case "$unit" in
      *.build)
        has_build=1
        break
        ;;
    esac
  done

  if [ "$has_build" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
    if tgdb_systemctl_try "$(tgdb_active_scope)" enable --now -- "$@" >/dev/null 2>&1; then
      return 0
    fi
  fi

  local failed=0
  for unit in "$@"; do
    if ! _quadlet_enable_now_by_filename "$unit"; then
      failed=1
    fi
  done

  [ "$failed" -eq 0 ]
}

_quadlet_remove_runtime_units_by_filenames() {
  local service=""
  if [ "$#" -gt 0 ] && [[ ! "$1" == *.* ]]; then
    service="$1"
    shift || true
  fi

  if [ "$#" -le 0 ]; then
    return 0
  fi

  local unit path
  for unit in "$@"; do
    [ -n "$unit" ] || continue
    path="$(_quadlet_runtime_unit_path "$unit" "$service")"
    if [ -n "$path" ] && [ -e "$path" ]; then
      if [ "$(tgdb_active_scope)" = "system" ]; then
        _tgdb_run_privileged rm -f "$path" 2>/dev/null || true
      else
        rm -f "$path" 2>/dev/null || true
      fi
    fi
  done
}

_install_quadlet_units_from_files() {
  local service=""
  local instance=""
  if [ "$#" -gt 0 ] && [ ! -f "$1" ]; then
    service="$1"
    shift || true
  fi
  if [ -n "$service" ] && [ "$#" -gt 0 ] && [ ! -f "$1" ]; then
    instance="$1"
    shift || true
  fi

  if [ "$#" -le 0 ]; then
    tgdb_fail "未提供任何 Quadlet 單元檔案" 1 || return $?
  fi

  local files=("$@")
  local f
  for f in "${files[@]}"; do
    if [ ! -f "$f" ]; then
      tgdb_fail "找不到 Quadlet 單元檔案：$f" 1 || return $?
    fi
  done

  local -a build_units=()
  local -a pod_units=()
  local -a container_units=()
  local -a other_units=()
  local f unit_filename
  for f in "${files[@]}"; do
    unit_filename="$(basename "$f")"
    case "${unit_filename##*.}" in
      build) build_units+=("$unit_filename") ;;
      pod) pod_units+=("$unit_filename") ;;
      container) container_units+=("$unit_filename") ;;
      *) other_units+=("$unit_filename") ;;
    esac
  done

  local images=() build_tags=() img unit_content
  for f in "${files[@]}"; do
    unit_content=$(cat "$f")
    while IFS= read -r img; do
      [ -n "$img" ] && build_tags+=("$img")
    done < <(_quadlet_extract_build_tags "$unit_content")
    while IFS= read -r img; do
      [ -n "$img" ] && images+=("$img")
    done < <(_quadlet_extract_images "$unit_content")
  done

  if [ ${#images[@]} -gt 0 ]; then
    local -A built_tags_seen=()
    for img in "${build_tags[@]}"; do
      [ -n "$img" ] && built_tags_seen["$img"]=1
    done

    local -A seen_images=()
    local -a uniq_images=()
    for img in "${images[@]}"; do
      [ -z "$img" ] && continue
      if [ -n "${built_tags_seen["$img"]+x}" ]; then
        continue
      fi
      if [ -z "${seen_images["$img"]+x}" ]; then
        seen_images["$img"]=1
        uniq_images+=("$img")
      fi
    done
    if [ ${#uniq_images[@]} -gt 0 ]; then
      _quadlet_pull_images "${uniq_images[@]}" || return $?
    fi
  fi

  local -a pending_build_units=()
  if [ ${#build_units[@]} -gt 0 ]; then
    for f in "${files[@]}"; do
      unit_filename="$(basename "$f")"
      case "${unit_filename##*.}" in
        build)
          if _quadlet_build_file_can_skip "$f"; then
            echo "ℹ️ 偵測到本機已存在映像，略過建置：$unit_filename"
          else
            pending_build_units+=("$unit_filename")
          fi
          ;;
      esac
    done
  fi

  if [ ${#pending_build_units[@]} -gt 0 ] && [ -n "$service" ] && declare -F _app_fn_exists >/dev/null 2>&1; then
    if _app_fn_exists "$service" pre_build; then
      _app_invoke "$service" pre_build "$instance" || return $?
    fi
  fi

  echo "⏳ 正在套用佈署並啟動服務，請稍等..."

  if ! _ensure_user_units_dir; then
    tgdb_fail "無法建立 Quadlet 單元目錄：$(_quadlet_user_units_dir)" 1 || return $?
    return 1
  fi

  for f in "${files[@]}"; do
    local dest
    local unit_filename unit_content runtime_content
    unit_filename="$(basename "$f")"
    unit_content="$(cat "$f")"
    runtime_content="$(_quadlet_runtime_unit_with_markers "$unit_content" "$service" "$instance")"
    dest="$(_quadlet_runtime_unit_path "$unit_filename" "$service")"
    if ! _write_file "$dest" "$runtime_content"; then
      tgdb_fail "寫入 Quadlet 單元失敗：$dest" 1 || return $?
      return 1
    fi
  done

  if ! _systemctl_user_try daemon-reload; then
    tgdb_fail "無法執行 $(tgdb_scope_label "$(tgdb_active_scope)") daemon-reload，請確認對應 systemd/DBus 環境可用。" 1 || return $?
    return 1
  fi

  if [ ${#pending_build_units[@]} -gt 0 ]; then
    echo "⏳ 正在建置映像，請稍等..."
    _quadlet_enable_now_bulk_by_filenames "${pending_build_units[@]}" || {
      tgdb_fail "Quadlet 建置單元執行失敗。" 1 || return $?
      return 1
    }
    if [ -n "$service" ] && declare -F _app_fn_exists >/dev/null 2>&1; then
      if _app_fn_exists "$service" post_build; then
        _app_invoke "$service" post_build "$instance" || return $?
      fi
    fi
  fi

  if [ ${#build_units[@]} -gt 0 ]; then
    _quadlet_remove_runtime_units_by_filenames "$service" "${build_units[@]}"
    if ! _systemctl_user_try daemon-reload; then
      tgdb_warn "建置完成，但無法在移除 .build 單元後執行 $(tgdb_scope_label "$(tgdb_active_scope)") daemon-reload。"
    fi
  fi

  _quadlet_enable_now_bulk_by_filenames "${other_units[@]}" || {
    tgdb_fail "Quadlet 其他單元啟用失敗。" 1 || return $?
    return 1
  }
  _quadlet_enable_now_bulk_by_filenames "${pod_units[@]}" || {
    tgdb_fail "Quadlet Pod 單元啟用失敗。" 1 || return $?
    return 1
  }
  _quadlet_enable_now_bulk_by_filenames "${container_units[@]}" || {
    tgdb_fail "Quadlet 容器單元啟用失敗。" 1 || return $?
    return 1
  }

  return 0
}

_install_service_quadlet_units_from_files() {
  local service="$1" instance="$2"
  shift 2 || true
  _install_quadlet_units_from_files "$service" "$instance" "$@"
}

_quadlet_apply_rshared_to_volumes() {
  local content="$1" propagation="${2:-none}" match_pattern="${3:-}"

  printf '%s' "$content" | awk -v prop="$propagation" -v pat="$match_pattern" '
    function _opts_remove(opts, tok,    n,a,i,out) {
      n = split(opts, a, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == tok) continue
        out = (out == "" ? a[i] : out "," a[i])
      }
      return out
    }
    function _opts_has(opts, tok,    n,a,i) {
      n = split(opts, a, ",")
      for (i = 1; i <= n; i++) if (a[i] == tok) return 1
      return 0
    }
    function _opts_add(opts, tok) {
      if (tok == "") return opts
      if (_opts_has(opts, tok)) return opts
      return (opts == "" ? tok : opts "," tok)
    }
    /^Volume=/ {
      if (pat != "" && $0 !~ pat) { print $0; next }
      split($0, a, "="); pre=a[1]; rest=a[2]

      # 解析 src:dest[:opts]，opts 以逗號分隔（例如 ro,Z,rshared）
      i1 = index(rest, ":")
      if (i1 == 0) { print $0; next }
      src = substr(rest, 1, i1-1)
      rem = substr(rest, i1+1)
      i2 = index(rem, ":")
      if (i2 == 0) {
        dest = rem
        opts = ""
      } else {
        dest = substr(rem, 1, i2-1)
        opts = substr(rem, i2+1)
      }

      # 移除既有 propagation 選項
      opts = _opts_remove(opts, "rprivate")
      opts = _opts_remove(opts, "private")
      opts = _opts_remove(opts, "rshared")
      opts = _opts_remove(opts, "shared")
      opts = _opts_remove(opts, "rslave")
      opts = _opts_remove(opts, "slave")

      if (prop ~ /^(rprivate|private|rshared|shared|rslave|slave)$/) {
        opts = _opts_add(opts, prop)
      }

      out = src ":" dest
      if (opts != "") out = out ":" opts
      print pre "=" out
      next
    }
    { print $0 }
  '
}

_quadlet_apply_selinux_to_volumes() {
  local content="$1" selinux_flag="${2:-none}" match_pattern="${3:-}"

  printf '%s' "$content" | awk -v sflag="$selinux_flag" -v pat="$match_pattern" '
    BEGIN {
      invert = 0
      if (pat ~ /^!/) {
        invert = 1
        pat = substr(pat, 2)
      }
    }
    function _opts_remove(opts, tok,    n,a,i,out) {
      n = split(opts, a, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == tok) continue
        out = (out == "" ? a[i] : out "," a[i])
      }
      return out
    }
    function _opts_has(opts, tok,    n,a,i) {
      n = split(opts, a, ",")
      for (i = 1; i <= n; i++) if (a[i] == tok) return 1
      return 0
    }
    function _opts_add(opts, tok) {
      if (tok == "") return opts
      if (_opts_has(opts, tok)) return opts
      return (opts == "" ? tok : opts "," tok)
    }
    /^Volume=/ {
      # 預設略過 podman.sock -> docker.sock 的掛載（不應套用 SELinux 標籤）
      if ($0 ~ /\/podman\/podman\.sock:/ || $0 ~ /:\/var\/run\/docker\.sock([:,]|$)/) { print $0; next }

      if (pat != "") {
        if (invert == 1) {
          if ($0 ~ pat) { print $0; next }
        } else {
          if ($0 !~ pat) { print $0; next }
        }
      }
      split($0, a, "="); pre=a[1]; rest=a[2]

      # 解析 src:dest[:opts]，opts 以逗號分隔（例如 ro,Z）
      i1 = index(rest, ":")
      if (i1 == 0) { print $0; next }
      src = substr(rest, 1, i1-1)
      rem = substr(rest, i1+1)
      i2 = index(rem, ":")
      if (i2 == 0) {
        dest = rem
        opts = ""
      } else {
        dest = substr(rem, 1, i2-1)
        opts = substr(rem, i2+1)
      }

      if (sflag == "Z" || sflag == "z") {
        opts = _opts_remove(opts, "Z")
        opts = _opts_remove(opts, "z")
        opts = _opts_add(opts, sflag)
      }

      out = src ":" dest
      if (opts != "") out = out ":" opts
      print pre "=" out
      next
    }
    { print $0 }
  '
}
