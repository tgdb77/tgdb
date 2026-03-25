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
  local scope
  scope="$(tgdb_active_scope)"

  if [ "$scope" = "system" ]; then
    if declare -F rm_system_units_dir >/dev/null 2>&1; then
      rm_system_units_dir
      return 0
    fi
    printf '%s\n' "/etc/containers/systemd"
    return 0
  fi

  if declare -F rm_user_units_dir >/dev/null 2>&1; then
    rm_user_units_dir
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
  local name="$1"
  shift
  local unit_content="$*"

  _quadlet_pull_images_from_unit "$unit_content" || return $?
  echo "⏳ 正在套用佈署並啟動服務，請稍等..."

  if ! _ensure_user_units_dir; then
    tgdb_fail "無法建立 Quadlet 單元目錄：$(_quadlet_user_units_dir)" 1 || return $?
    return 1
  fi
  local unit_path
  unit_path="$(_quadlet_user_units_dir)/$name.container"
  if ! _write_file "$unit_path" "$unit_content"; then
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

  if command -v systemctl >/dev/null 2>&1; then
    if tgdb_systemctl_try "$(tgdb_active_scope)" enable --now -- "$@" >/dev/null 2>&1; then
      return 0
    fi
  fi

  local unit
  local failed=0
  for unit in "$@"; do
    if ! _quadlet_enable_now_by_filename "$unit"; then
      failed=1
    fi
  done

  [ "$failed" -eq 0 ]
}

_install_quadlet_units_from_files() {
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

  local images=() img unit_content
  for f in "${files[@]}"; do
    unit_content=$(cat "$f")
    while IFS= read -r img; do
      [ -n "$img" ] && images+=("$img")
    done < <(_quadlet_extract_images "$unit_content")
  done

  if [ ${#images[@]} -gt 0 ]; then
    local -A seen_images=()
    local -a uniq_images=()
    for img in "${images[@]}"; do
      [ -z "$img" ] && continue
      if [ -z "${seen_images["$img"]+x}" ]; then
        seen_images["$img"]=1
        uniq_images+=("$img")
      fi
    done
    _quadlet_pull_images "${uniq_images[@]}" || return $?
  fi

  echo "⏳ 正在套用佈署並啟動服務，請稍等..."

  if ! _ensure_user_units_dir; then
    tgdb_fail "無法建立 Quadlet 單元目錄：$(_quadlet_user_units_dir)" 1 || return $?
    return 1
  fi

  for f in "${files[@]}"; do
    local dest
    dest="$(_quadlet_user_units_dir)/$(basename "$f")"
    if ! _write_file "$dest" "$(cat "$f")"; then
      tgdb_fail "寫入 Quadlet 單元失敗：$dest" 1 || return $?
      return 1
    fi
  done

  if ! _systemctl_user_try daemon-reload; then
    tgdb_fail "無法執行 $(tgdb_scope_label "$(tgdb_active_scope)") daemon-reload，請確認對應 systemd/DBus 環境可用。" 1 || return $?
    return 1
  fi

  local -a pod_units=()
  local -a container_units=()
  for f in "${files[@]}"; do
    local unit_filename
    unit_filename="$(basename "$f")"
    case "${unit_filename##*.}" in
      pod) pod_units+=("$unit_filename") ;;
      container) container_units+=("$unit_filename") ;;
    esac
  done

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
