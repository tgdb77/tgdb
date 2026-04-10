#!/bin/bash

# 全系統備份：systemd / Quadlet / 冷備份控制
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_BACKUP_UNITS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_UNITS_LOADED=1

_backup_has_systemctl_user() {
  command -v systemctl >/dev/null 2>&1
}

_backup_runtime_quadlet_archive_root() {
  printf '%s\n' "$BACKUP_QUADLET_RUNTIME_DIR/tgdb"
}

_backup_runtime_quadlet_archive_service_dir() {
  local service="$1"
  [ -n "${service:-}" ] || return 1
  printf '%s\n' "$(_backup_runtime_quadlet_archive_root)/$service"
}

_backup_iter_runtime_quadlet_records() {
  rm_list_tgdb_runtime_quadlet_files_by_mode rootless 2>/dev/null || true
}

_backup_iter_runtime_quadlet_paths() {
  local path
  while IFS=$'\t' read -r _scope _service _base path _managed; do
    [ -n "${path:-}" ] || continue
    printf '%s\n' "$path"
  done < <(_backup_iter_runtime_quadlet_records)
}

_backup_iter_runtime_quadlet_basenames() {
  local base
  while IFS=$'\t' read -r _scope _service base _path _managed; do
    [ -n "${base:-}" ] || continue
    printf '%s\n' "$base"
  done < <(_backup_iter_runtime_quadlet_records)
}

_backup_extract_pod_unit_from_container_file() {
  local path="$1"
  [ -f "$path" ] || return 0

  local pod
  pod="$(awk -F= '
    /^[[:space:]]*Pod[[:space:]]*=/{
      line=$0
      sub(/^[[:space:]]*Pod[[:space:]]*=/, "", line)
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }' "$path" 2>/dev/null || true)"
  [ -n "${pod:-}" ] || return 0
  printf '%s\n' "$pod"
}

_backup_unit_candidates_by_filename() {
  local fname="$1"
  [ -n "${fname:-}" ] || return 0

  local base="${fname%.*}"
  local ext="${fname##*.}"
  case "$ext" in
    container)
      printf '%s\n' "$fname" "$base.service" "container-$base.service"
      ;;
    pod)
      printf '%s\n' "$fname" "pod-$base.service" "$base.service"
      ;;
    *)
      printf '%s\n' "$fname" "$base.service"
      ;;
  esac
}

_backup_unit_is_active_by_filename() {
  local fname="$1"
  [ -n "${fname:-}" ] || return 1
  _backup_has_systemctl_user || return 1

  local -a candidates=()
  mapfile -t candidates < <(_backup_unit_candidates_by_filename "$fname")
  _systemctl_user_try is-active -- "${candidates[@]}" >/dev/null 2>&1
}

_backup_stop_unit_by_filename() {
  local fname="$1"
  [ -n "${fname:-}" ] || return 0
  _backup_has_systemctl_user || return 0

  local -a candidates=()
  mapfile -t candidates < <(_backup_unit_candidates_by_filename "$fname")
  _systemctl_user_try stop -- "${candidates[@]}" >/dev/null 2>&1 || true
}

_backup_start_unit_by_filename() {
  local fname="$1"
  [ -n "${fname:-}" ] || return 0
  _backup_has_systemctl_user || return 0

  local -a candidates=()
  mapfile -t candidates < <(_backup_unit_candidates_by_filename "$fname")
  _systemctl_user_try start --no-block -- "${candidates[@]}" >/dev/null 2>&1 || true
}

_backup_collect_active_tgdb_units() {
  BACKUP_ACTIVE_CONTAINERS=()
  BACKUP_ACTIVE_PODS=()

  _backup_has_systemctl_user || return 0

  local -A seen_cont=()
  local -A seen_pod=()

  local f fname pod
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fname="${f##*/}"
    if _backup_unit_is_active_by_filename "$fname"; then
      if [ -z "${seen_cont["$fname"]+x}" ]; then
        seen_cont["$fname"]=1
        BACKUP_ACTIVE_CONTAINERS+=("$fname")
      fi
    fi

    pod="$(_backup_extract_pod_unit_from_container_file "$f" || true)"
    if [ -n "${pod:-}" ] && _backup_unit_is_active_by_filename "$pod"; then
      if [ -z "${seen_pod["$pod"]+x}" ]; then
        seen_pod["$pod"]=1
        BACKUP_ACTIVE_PODS+=("$pod")
      fi
    fi
  done < <(_backup_iter_runtime_quadlet_paths | awk '/\.container$/')
}

_backup_collect_active_user_units() {
  BACKUP_ACTIVE_CONTAINERS=()
  BACKUP_ACTIVE_PODS=()

  _backup_has_systemctl_user || return 0

  local -A seen_cont=()
  local -A seen_pod=()

  local f fname
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fname="${f##*/}"
    if _backup_unit_is_active_by_filename "$fname"; then
      if [ -z "${seen_cont["$fname"]+x}" ]; then
        seen_cont["$fname"]=1
        BACKUP_ACTIVE_CONTAINERS+=("$fname")
      fi
    fi
  done < <(_backup_iter_runtime_quadlet_paths | awk '/\.container$/')

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fname="${f##*/}"
    if _backup_unit_is_active_by_filename "$fname"; then
      if [ -z "${seen_pod["$fname"]+x}" ]; then
        seen_pod["$fname"]=1
        BACKUP_ACTIVE_PODS+=("$fname")
      fi
    fi
  done < <(_backup_iter_runtime_quadlet_paths | awk '/\.pod$/')
}

_backup_stop_for_cold_snapshot() {
  if ! _backup_has_systemctl_user; then
    tgdb_warn "未偵測到 systemctl --user，無法自動停機進行冷備份；Postgres/SQLite 可能產生不一致備份。"
    return 0
  fi

  _backup_collect_active_tgdb_units

  if [ ${#BACKUP_ACTIVE_CONTAINERS[@]} -eq 0 ] && [ ${#BACKUP_ACTIVE_PODS[@]} -eq 0 ]; then
    return 0
  fi

  echo "⏸️ 正在停止服務（冷備份，避免 Postgres/SQLite 備份不一致）..."

  local u
  for u in "${BACKUP_ACTIVE_CONTAINERS[@]}"; do
    _backup_stop_unit_by_filename "$u"
  done
  for u in "${BACKUP_ACTIVE_PODS[@]}"; do
    _backup_stop_unit_by_filename "$u"
  done
}

_backup_resume_after_cold_snapshot() {
  if [ ${#BACKUP_ACTIVE_CONTAINERS[@]} -eq 0 ] && [ ${#BACKUP_ACTIVE_PODS[@]} -eq 0 ]; then
    return 0
  fi

  echo "▶️ 正在恢復服務...具體狀態查看日誌"

  local u
  for u in "${BACKUP_ACTIVE_PODS[@]}"; do
    _backup_start_unit_by_filename "$u"
  done
  for u in "${BACKUP_ACTIVE_CONTAINERS[@]}"; do
    _backup_start_unit_by_filename "$u"
  done
}

_backup_clear_user_quadlet_units() {
  local -a unit_records=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && unit_records+=("$line")
  done < <(_backup_iter_runtime_quadlet_records)

  [ ${#unit_records[@]} -gt 0 ] || return 0

  if _backup_has_systemctl_user; then
    _systemctl_user_try daemon-reload >/dev/null 2>&1 || true
    local unit
    for line in "${unit_records[@]}"; do
      IFS=$'\t' read -r _scope _service unit _path _managed <<< "$line"
      [ -n "${unit:-}" ] || continue
      local -a candidates=()
      mapfile -t candidates < <(_backup_unit_candidates_by_filename "$unit")
      _systemctl_user_try disable --now -- "${candidates[@]}" >/dev/null 2>&1 || true
    done
  fi

  local removed=0 failed=0
  local path
  for line in "${unit_records[@]}"; do
    IFS=$'\t' read -r _scope _service _base path _managed <<< "$line"
    [ -n "${path:-}" ] || continue
    if rm -f -- "$path" 2>/dev/null; then
      removed=$((removed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  if [ "$failed" -gt 0 ]; then
    tgdb_warn "清理 TGDB 管理的 Quadlet 單元時有失敗（成功=$removed / 失敗=$failed）。"
    return 1
  fi

  echo "ℹ️ 已清理 TGDB 管理的 Quadlet 單元（共 $removed 個）"
  return 0
}

_backup_unit_filename_matches_targets() {
    local fname="$1"
    shift || true
    local target
    for target in "$@"; do
        if _backup_instance_name_matches_basename "$fname" "$target"; then
            return 0
        fi
    done
    return 1
}

_backup_collect_active_units_for_instances() {
    BACKUP_ACTIVE_CONTAINERS=()
    BACKUP_ACTIVE_PODS=()

    [ "$#" -gt 0 ] || return 0
    _backup_has_systemctl_user || return 0

    local -A seen_cont=()
    local -A seen_pod=()
    local f fname pod
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        fname="${f##*/}"
        if ! _backup_unit_filename_matches_targets "$fname" "$@"; then
            continue
        fi
        if _backup_unit_is_active_by_filename "$fname"; then
            if [ -z "${seen_cont["$fname"]+x}" ]; then
                seen_cont["$fname"]=1
                BACKUP_ACTIVE_CONTAINERS+=("$fname")
            fi
        fi
        pod="$(_backup_extract_pod_unit_from_container_file "$f" || true)"
        if [ -n "${pod:-}" ] && _backup_unit_is_active_by_filename "$pod"; then
            if [ -z "${seen_pod["$pod"]+x}" ]; then
                seen_pod["$pod"]=1
                BACKUP_ACTIVE_PODS+=("$pod")
            fi
        fi
    done < <(_backup_iter_runtime_quadlet_paths | awk '/\.container$/')

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        fname="${f##*/}"
        if ! _backup_unit_filename_matches_targets "$fname" "$@"; then
            continue
        fi
        if _backup_unit_is_active_by_filename "$fname"; then
            if [ -z "${seen_pod["$fname"]+x}" ]; then
                seen_pod["$fname"]=1
                BACKUP_ACTIVE_PODS+=("$fname")
            fi
        fi
    done < <(_backup_iter_runtime_quadlet_paths | awk '/\.pod$/')
}

_backup_stop_selected_for_cold_snapshot() {
    _backup_collect_active_units_for_instances "$@"
    if [ ${#BACKUP_ACTIVE_CONTAINERS[@]} -eq 0 ] && [ ${#BACKUP_ACTIVE_PODS[@]} -eq 0 ]; then
        return 0
    fi

    echo "⏸️ 正在停止指定實例相關服務（冷備份）..."
    local u
    for u in "${BACKUP_ACTIVE_CONTAINERS[@]}"; do
        _backup_stop_unit_by_filename "$u"
    done
    for u in "${BACKUP_ACTIVE_PODS[@]}"; do
        _backup_stop_unit_by_filename "$u"
    done
}

_backup_enable_units_by_filenames() {
    [ "$#" -gt 0 ] || return 0
    _backup_has_systemctl_user || return 0

    _systemctl_user_try daemon-reload >/dev/null 2>&1 || true

    local -a networks=() volumes=() devices=() pods=() containers=() others=()
    local u
    for u in "$@"; do
        [ -n "$u" ] || continue
        case "$u" in
            *.network) networks+=("$u") ;;
            *.volume) volumes+=("$u") ;;
            *.device) devices+=("$u") ;;
            *.pod) pods+=("$u") ;;
            *.container) containers+=("$u") ;;
            *) others+=("$u") ;;
        esac
    done

    for u in "${networks[@]}"; do _quadlet_enable_now_by_filename "$u"; done
    for u in "${volumes[@]}"; do _quadlet_enable_now_by_filename "$u"; done
    for u in "${devices[@]}"; do _quadlet_enable_now_by_filename "$u"; done
    for u in "${pods[@]}"; do _quadlet_enable_now_by_filename "$u"; done
    for u in "${containers[@]}"; do _quadlet_enable_now_by_filename "$u"; done
    for u in "${others[@]}"; do _quadlet_enable_now_by_filename "$u"; done
}

_backup_runtime_quadlet_rel_path_from_root() {
    local path="$1"
    [ -n "${path:-}" ] || return 1
    case "$path" in
        "$CONTAINERS_SYSTEMD_DIR"/*)
            printf '%s\n' "${path#"$CONTAINERS_SYSTEMD_DIR"/}"
            return 0
            ;;
    esac
    return 1
}

_backup_stage_runtime_quadlet_tree() {
    local stage_dir="$1"
    [ -n "${stage_dir:-}" ] || return 1

    rm -rf -- "$stage_dir" 2>/dev/null || true
    mkdir -p "$stage_dir" 2>/dev/null || return 1

    local copied=0
    local path rel dest
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        rel="$(_backup_runtime_quadlet_rel_path_from_root "$path" 2>/dev/null || true)"
        [ -n "${rel:-}" ] || continue
        dest="$stage_dir/$rel"
        mkdir -p "$(dirname "$dest")" 2>/dev/null || return 1
        if ! podman unshare cp -a "$path" "$dest"; then
            tgdb_warn "同步 Quadlet 單元失敗：$path"
            continue
        fi
        copied=$((copied + 1))
    done < <(_backup_iter_runtime_quadlet_paths)

    if [ "$copied" -le 0 ]; then
        rm -rf -- "$stage_dir" 2>/dev/null || true
        return 1
    fi
    return 0
}

_backup_collect_unit_filenames_from_dir() {
    local dir="$1"
    [ -d "$dir" ] || return 0

    find "$dir" -type f \
      \( -name "*.container" -o -name "*.pod" -o -name "*.network" -o -name "*.volume" -o -name "*.device" -o -name "*.kube" -o -name "*.image" \) \
      -printf '%f\n' 2>/dev/null | awk 'NF && !seen[$0]++'
}

_backup_find_runtime_quadlet_dir_in_tree() {
    local base_dir="$1"
    [ -n "${base_dir:-}" ] || return 1

    if [ -d "$base_dir/$BACKUP_QUADLET_RUNTIME_ARCHIVE_DIRNAME" ]; then
        printf '%s\n' "$base_dir/$BACKUP_QUADLET_RUNTIME_ARCHIVE_DIRNAME"
        return 0
    fi
    if [ -d "$base_dir/quadlet" ]; then
        printf '%s\n' "$base_dir/quadlet"
        return 0
    fi
    return 1
}

_backup_restore_runtime_quadlet_tree() {
    local src_dir="$1"
    [ -d "$src_dir" ] || return 1

    mkdir -p "$CONTAINERS_SYSTEMD_DIR" 2>/dev/null || return 1
    if ! podman unshare cp -a "$src_dir/." "$CONTAINERS_SYSTEMD_DIR/"; then
        return 1
    fi
    return 0
}

# --- 備份與還原 ---
