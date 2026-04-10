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

_backup_unit_file_references_tgdb_dir() {
  local path="$1"
  [ -n "${TGDB_DIR:-}" ] || return 1
  [ -f "$path" ] || return 1
  grep -Fq "$TGDB_DIR/" "$path" 2>/dev/null
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

  [ -d "$CONTAINERS_SYSTEMD_DIR" ] || return 0
  _backup_has_systemctl_user || return 0

  local -A seen_cont=()
  local -A seen_pod=()

  local f fname pod
  while IFS= read -r -d $'\0' f; do
    _backup_unit_file_references_tgdb_dir "$f" || continue

    fname="$(basename "$f")"
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
  done < <(find "$CONTAINERS_SYSTEMD_DIR" -maxdepth 1 -type f -name "*.container" -print0 2>/dev/null)
}

_backup_collect_active_user_units() {
  BACKUP_ACTIVE_CONTAINERS=()
  BACKUP_ACTIVE_PODS=()

  [ -d "$CONTAINERS_SYSTEMD_DIR" ] || return 0
  _backup_has_systemctl_user || return 0

  local -A seen_cont=()
  local -A seen_pod=()

  local f fname
  while IFS= read -r -d $'\0' f; do
    fname="$(basename "$f")"
    if _backup_unit_is_active_by_filename "$fname"; then
      if [ -z "${seen_cont["$fname"]+x}" ]; then
        seen_cont["$fname"]=1
        BACKUP_ACTIVE_CONTAINERS+=("$fname")
      fi
    fi
  done < <(find "$CONTAINERS_SYSTEMD_DIR" -maxdepth 1 -type f -name "*.container" -print0 2>/dev/null)

  while IFS= read -r -d $'\0' f; do
    fname="$(basename "$f")"
    if _backup_unit_is_active_by_filename "$fname"; then
      if [ -z "${seen_pod["$fname"]+x}" ]; then
        seen_pod["$fname"]=1
        BACKUP_ACTIVE_PODS+=("$fname")
      fi
    fi
  done < <(find "$CONTAINERS_SYSTEMD_DIR" -maxdepth 1 -type f -name "*.pod" -print0 2>/dev/null)
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

_backup_enable_all_units_from_units_dir() {
  [ -d "$CONTAINERS_SYSTEMD_DIR" ] || return 0
  _backup_has_systemctl_user || return 0

  _systemctl_user_try daemon-reload >/dev/null 2>&1 || true

  local -a networks=() volumes=() devices=() pods=() containers=()
  local f b
  while IFS= read -r -d $'\0' f; do
    b="$(basename "$f")"
    case "$b" in
      *.network) networks+=("$b") ;;
      *.volume) volumes+=("$b") ;;
      *.device) devices+=("$b") ;;
      *.pod) pods+=("$b") ;;
      *.container) containers+=("$b") ;;
    esac
  done < <(find "$CONTAINERS_SYSTEMD_DIR" -maxdepth 1 -type f \( -name "*.network" -o -name "*.volume" -o -name "*.device" -o -name "*.pod" -o -name "*.container" \) -print0 2>/dev/null)

  local u
  for u in "${networks[@]}"; do _quadlet_enable_now_by_filename "$u"; done
  for u in "${volumes[@]}"; do _quadlet_enable_now_by_filename "$u"; done
  for u in "${devices[@]}"; do _quadlet_enable_now_by_filename "$u"; done
  for u in "${pods[@]}"; do _quadlet_enable_now_by_filename "$u"; done
  for u in "${containers[@]}"; do _quadlet_enable_now_by_filename "$u"; done
}

_backup_clear_user_quadlet_units() {
  [ -d "$CONTAINERS_SYSTEMD_DIR" ] || return 0

  local -a unit_files=()
  local f
  while IFS= read -r -d $'\0' f; do
    unit_files+=("$(basename "$f")")
  done < <(find "$CONTAINERS_SYSTEMD_DIR" -maxdepth 1 -type f \
    \( -name "*.container" -o -name "*.pod" -o -name "*.network" -o -name "*.volume" -o -name "*.device" -o -name "*.kube" -o -name "*.image" -o -name "*.build" \) \
    -print0 2>/dev/null)

  [ ${#unit_files[@]} -gt 0 ] || return 0

  if _backup_has_systemctl_user; then
    _systemctl_user_try daemon-reload >/dev/null 2>&1 || true
    local unit
    for unit in "${unit_files[@]}"; do
      local -a candidates=()
      mapfile -t candidates < <(_backup_unit_candidates_by_filename "$unit")
      _systemctl_user_try disable --now -- "${candidates[@]}" >/dev/null 2>&1 || true
    done
  fi

  local removed=0 failed=0
  for f in "${unit_files[@]}"; do
    if rm -f -- "$CONTAINERS_SYSTEMD_DIR/$f" 2>/dev/null; then
      removed=$((removed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  if [ "$failed" -gt 0 ]; then
    tgdb_warn "清理既有 Quadlet 單元時有失敗（成功=$removed / 失敗=$failed）：$CONTAINERS_SYSTEMD_DIR"
    return 1
  fi

  echo "ℹ️ 已清理既有 Quadlet 單元：$CONTAINERS_SYSTEMD_DIR（共 $removed 個）"
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
    [ -d "$CONTAINERS_SYSTEMD_DIR" ] || return 0
    _backup_has_systemctl_user || return 0

    local -A seen_cont=()
    local -A seen_pod=()
    local f fname pod
    while IFS= read -r -d $'\0' f; do
        fname="$(basename "$f")"
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
    done < <(find "$CONTAINERS_SYSTEMD_DIR" -maxdepth 1 -type f -name "*.container" -print0 2>/dev/null)

    while IFS= read -r -d $'\0' f; do
        fname="$(basename "$f")"
        if ! _backup_unit_filename_matches_targets "$fname" "$@"; then
            continue
        fi
        if _backup_unit_is_active_by_filename "$fname"; then
            if [ -z "${seen_pod["$fname"]+x}" ]; then
                seen_pod["$fname"]=1
                BACKUP_ACTIVE_PODS+=("$fname")
            fi
        fi
    done < <(find "$CONTAINERS_SYSTEMD_DIR" -maxdepth 1 -type f -name "*.pod" -print0 2>/dev/null)
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
    [ -d "$CONTAINERS_SYSTEMD_DIR" ] || return 0
    _backup_has_systemctl_user || return 0

    _systemctl_user_try daemon-reload >/dev/null 2>&1 || true

    local u
    for u in "$@"; do
        [ -n "$u" ] || continue
        _quadlet_enable_now_by_filename "$u"
    done
}

# --- 備份與還原 ---

