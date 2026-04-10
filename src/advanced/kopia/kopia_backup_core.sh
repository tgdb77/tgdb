#!/bin/bash

# Kopia 備份：核心共用函式
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_BACKUP_CORE_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_BACKUP_CORE_LOADED=1

KOPIA_BACKUP_SERVICE="tgdb-kopia-backup.service"
KOPIA_BACKUP_TIMER="tgdb-kopia-backup.timer"
KOPIA_ACTIVE_CONTAINERS=()
KOPIA_ACTIVE_PODS=()

_kopia_backup_status_file() {
  printf '%s\n' "$(rm_persist_config_dir)/backup/kopia_status.conf"
}

_write_user_unit() {
  tgdb_timer_write_user_unit "$1" "$2"
}

_service_file() {
  tgdb_timer_unit_path "$KOPIA_BACKUP_SERVICE"
}

_timer_file() {
  tgdb_timer_unit_path "$KOPIA_BACKUP_TIMER"
}

_timer_oncalendar_get() {
  tgdb_timer_schedule_get "$KOPIA_BACKUP_TIMER" "OnCalendar"
}

_kopia_ignore_file() {
  printf '%s\n' "$TGDB_DIR/.kopiaignore"
}

_kopia_lock_dir() {
  local backup_root
  backup_root="$(tgdb_backup_root)"
  printf '%s\n' "$backup_root/.tgdb_kopia_backup.lock.d"
}

_kopia_lock_acquire() {
  local lock_dir="$1"
  [ -n "${lock_dir:-}" ] || return 1

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" >"$lock_dir/pid" 2>/dev/null || true
    date +%Y%m%d-%H%M%S >"$lock_dir/created_at" 2>/dev/null || true
    return 0
  fi

  local pid=""
  pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  if [[ "${pid:-}" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    tgdb_warn "偵測到備份程序正在執行（pid=$pid），本次略過。"
    return 1
  fi

  # stale lock
  rm -rf "$lock_dir" 2>/dev/null || true
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" >"$lock_dir/pid" 2>/dev/null || true
    date +%Y%m%d-%H%M%S >"$lock_dir/created_at" 2>/dev/null || true
    return 0
  fi

  tgdb_warn "無法取得 lock：$lock_dir"
  return 1
}

_kopia_lock_release() {
  local lock_dir="$1"
  [ -n "${lock_dir:-}" ] || return 0
  rm -rf "$lock_dir" 2>/dev/null || true
  return 0
}

_kopia_instance_env_file() {
  printf '%s\n' "$TGDB_DIR/kopia/.env"
}

_kopia_env_value() {
  local key="$1"
  local env_file
  env_file="$(_kopia_instance_env_file)"
  [ -n "${key:-}" ] || return 1
  [ -f "$env_file" ] || return 1

  awk -F= -v want="$key" '
    /^[[:space:]]*#/ { next }
    NF < 2 { next }
    {
      k=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k==want) {
        v=substr($0, index($0, "=")+1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^"|"$/, "", v)
        print v
        exit
      }
    }
  ' "$env_file" 2>/dev/null
}

_kopia_exec() {
  local name="${1:-kopia}"
  shift || true

  local kopia_password
  kopia_password="$(_kopia_env_value "KOPIA_PASSWORD" 2>/dev/null || true)"

  if [ -n "${kopia_password:-}" ]; then
    podman exec --env "KOPIA_PASSWORD=$kopia_password" "$name" "$@"
  else
    podman exec "$name" "$@"
  fi
}

_kopia_wait_exec_ready() {
  local name="${1:-kopia}"
  local tries="${2:-15}"
  local i
  for ((i=1; i<=tries; i++)); do
    if podman exec "$name" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  tgdb_fail "Kopia 容器尚未就緒：$name" 1 || true
  return 1
}

_kopia_require_interactive() {
  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi
  return 0
}

_kopia_has_systemctl_user() {
  command -v systemctl >/dev/null 2>&1
}

_kopia_volume_dir() {
  local backup_root metadata_file volume_dir
  backup_root="$(tgdb_backup_root)"
  metadata_file="$TGDB_DIR/kopia/.tgdb_volume_dir"
  if [ -f "$metadata_file" ]; then
    volume_dir="$(head -n 1 "$metadata_file" 2>/dev/null || true)"
  fi
  if [ -z "${volume_dir:-}" ]; then
    volume_dir="$backup_root/volume/kopia/kopia"
  fi
  printf '%s\n' "$volume_dir"
}

_kopia_remove_path_best_effort() {
  local target="$1"
  [ -n "${target:-}" ] || return 0
  [ -e "$target" ] || return 0

  if command -v podman >/dev/null 2>&1; then
    podman unshare rm -rf -- "$target" 2>/dev/null || true
  fi

  if [ -e "$target" ]; then
    rm -rf -- "$target" 2>/dev/null || true
  fi

  [ ! -e "$target" ]
}

_kopia_unit_candidates_by_filename() {
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

_kopia_unit_is_active_by_filename() {
  local fname="$1"
  [ -n "${fname:-}" ] || return 1
  _kopia_has_systemctl_user || return 1

  local -a candidates=()
  mapfile -t candidates < <(_kopia_unit_candidates_by_filename "$fname")
  _systemctl_user_try is-active -- "${candidates[@]}" >/dev/null 2>&1
}

_kopia_stop_unit_by_filename() {
  local fname="$1"
  [ -n "${fname:-}" ] || return 0
  _kopia_has_systemctl_user || return 0

  local -a candidates=()
  mapfile -t candidates < <(_kopia_unit_candidates_by_filename "$fname")
  _systemctl_user_try stop -- "${candidates[@]}" >/dev/null 2>&1 || true
}

_kopia_start_unit_by_filename() {
  local fname="$1"
  [ -n "${fname:-}" ] || return 0
  _kopia_has_systemctl_user || return 0

  local -a candidates=()
  mapfile -t candidates < <(_kopia_unit_candidates_by_filename "$fname")
  _systemctl_user_try start --no-block -- "${candidates[@]}" >/dev/null 2>&1 || true
}

_kopia_quadlet_runtime_archive_dirname() {
  printf '%s\n' "quadlet-runtime"
}

_kopia_quadlet_runtime_stage_dir() {
  local backup_root
  backup_root="$(tgdb_backup_root)"
  printf '%s\n' "$backup_root/$(_kopia_quadlet_runtime_archive_dirname)"
}

_kopia_iter_runtime_quadlet_records() {
  rm_list_tgdb_runtime_quadlet_files_by_mode rootless 2>/dev/null || true
}

_kopia_iter_runtime_quadlet_paths() {
  local path
  while IFS=$'\t' read -r _scope _service _base path _managed; do
    [ -n "${path:-}" ] || continue
    printf '%s\n' "$path"
  done < <(_kopia_iter_runtime_quadlet_records)
}

_kopia_runtime_quadlet_rel_path_from_root() {
  local path="$1"
  local root
  root="$(rm_quadlet_root_dir_by_mode rootless 2>/dev/null || rm_user_units_dir)"
  [ -n "${path:-}" ] || return 1
  case "$path" in
    "$root"/*)
      printf '%s\n' "${path#"$root"/}"
      return 0
      ;;
  esac
  return 1
}

_kopia_collect_unit_filenames_from_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0

  find "$dir" -type f \
    \( -name "*.container" -o -name "*.pod" -o -name "*.network" -o -name "*.volume" -o -name "*.device" -o -name "*.kube" -o -name "*.image" \) \
    -printf '%f\n' 2>/dev/null | awk 'NF && !seen[$0]++'
}

_kopia_find_runtime_quadlet_dir_in_tree() {
  local base_dir="$1"
  [ -n "${base_dir:-}" ] || return 1

  if [ -d "$base_dir/$(_kopia_quadlet_runtime_archive_dirname)" ]; then
    printf '%s\n' "$base_dir/$(_kopia_quadlet_runtime_archive_dirname)"
    return 0
  fi
  if [ -d "$base_dir/quadlet" ]; then
    printf '%s\n' "$base_dir/quadlet"
    return 0
  fi
  return 1
}

_kopia_restore_runtime_quadlet_tree() {
  local src_dir="$1"
  local dst_dir
  dst_dir="$(rm_quadlet_root_dir_by_mode rootless 2>/dev/null || rm_user_units_dir)"
  [ -d "$src_dir" ] || return 1
  mkdir -p "$dst_dir" 2>/dev/null || return 1
  cp -a "$src_dir/." "$dst_dir/" 2>/dev/null
}

_kopia_stage_runtime_quadlet_tree() {
  local stage_dir="$1"
  [ -n "${stage_dir:-}" ] || return 1

  rm -rf -- "$stage_dir" 2>/dev/null || true
  mkdir -p "$stage_dir" 2>/dev/null || return 1

  local copied=0 path rel dest
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    rel="$(_kopia_runtime_quadlet_rel_path_from_root "$path" 2>/dev/null || true)"
    [ -n "${rel:-}" ] || continue
    dest="$stage_dir/$rel"
    mkdir -p "$(dirname "$dest")" 2>/dev/null || return 1
    if ! cp -a "$path" "$dest" 2>/dev/null; then
      tgdb_warn "同步 Quadlet runtime 失敗：$path"
      continue
    fi
    copied=$((copied + 1))
  done < <(_kopia_iter_runtime_quadlet_paths)

  if [ "$copied" -le 0 ]; then
    rm -rf -- "$stage_dir" 2>/dev/null || true
    return 1
  fi
  return 0
}

_kopia_enable_units_by_filenames() {
  [ "$#" -gt 0 ] || return 0
  _kopia_has_systemctl_user || return 0

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

_kopia_collect_active_user_units() {
  KOPIA_ACTIVE_CONTAINERS=()
  KOPIA_ACTIVE_PODS=()

  _kopia_has_systemctl_user || return 0

  local -A seen_cont=()
  local -A seen_pod=()
  local f fname

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fname="${f##*/}"
    if _kopia_unit_is_active_by_filename "$fname"; then
      if [ -z "${seen_cont["$fname"]+x}" ]; then
        seen_cont["$fname"]=1
        KOPIA_ACTIVE_CONTAINERS+=("$fname")
      fi
    fi
  done < <(_kopia_iter_runtime_quadlet_paths | awk '/\.container$/')

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fname="${f##*/}"
    if _kopia_unit_is_active_by_filename "$fname"; then
      if [ -z "${seen_pod["$fname"]+x}" ]; then
        seen_pod["$fname"]=1
        KOPIA_ACTIVE_PODS+=("$fname")
      fi
    fi
  done < <(_kopia_iter_runtime_quadlet_paths | awk '/\.pod$/')
}

_kopia_resume_active_units() {
  if [ ${#KOPIA_ACTIVE_CONTAINERS[@]} -eq 0 ] && [ ${#KOPIA_ACTIVE_PODS[@]} -eq 0 ]; then
    return 0
  fi

  local u
  for u in "${KOPIA_ACTIVE_PODS[@]}"; do
    _kopia_start_unit_by_filename "$u"
  done
  for u in "${KOPIA_ACTIVE_CONTAINERS[@]}"; do
    _kopia_start_unit_by_filename "$u"
  done
  return 0
}

_kopia_enable_all_units_from_units_dir() {
  _kopia_has_systemctl_user || return 0

  local -a units=()
  local u
  while IFS= read -r u; do
    [ -n "$u" ] && units+=("$u")
  done < <(_kopia_collect_unit_filenames_from_dir "$(rm_quadlet_root_dir_by_mode rootless 2>/dev/null || rm_user_units_dir)")

  _kopia_enable_units_by_filenames "${units[@]}"
}

_kopia_clear_user_quadlet_units() {
  local -a records=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && records+=("$line")
  done < <(_kopia_iter_runtime_quadlet_records)

  [ ${#records[@]} -gt 0 ] || return 0

  if _kopia_has_systemctl_user; then
    _systemctl_user_try daemon-reload >/dev/null 2>&1 || true
    local unit
    local path
    for line in "${records[@]}"; do
      IFS=$'\t' read -r _scope _service unit path _managed <<< "$line"
      [ -n "${unit:-}" ] || continue
      local -a candidates=()
      mapfile -t candidates < <(_kopia_unit_candidates_by_filename "$unit")
      _systemctl_user_try disable --now -- "${candidates[@]}" >/dev/null 2>&1 || true
    done
  fi

  local removed=0 failed=0
  local path
  for line in "${records[@]}"; do
    IFS=$'\t' read -r _scope _service _base path _managed <<< "$line"
    [ -n "${path:-}" ] || continue
    if rm -f -- "$path" 2>/dev/null; then
      removed=$((removed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  if [ "$failed" -gt 0 ]; then
    tgdb_warn "清理 TGDB 管理的 Quadlet runtime 時有失敗（成功=$removed / 失敗=$failed）。"
    return 1
  fi

  echo "ℹ️ 已清理 TGDB 管理的 Quadlet runtime（共 $removed 個）"
  return 0
}

_kopia_sync_quadlet_to_user_units() {
  local backup_root src_dir dst_dir
  backup_root="$(tgdb_backup_root)"
  src_dir="$(_kopia_find_runtime_quadlet_dir_in_tree "$backup_root" 2>/dev/null || true)"
  dst_dir="$(rm_quadlet_root_dir_by_mode rootless 2>/dev/null || rm_user_units_dir)"

  if [ -z "${src_dir:-}" ] || [ ! -d "$src_dir" ]; then
    tgdb_warn "未找到還原後 Quadlet runtime 目錄（略過同步）。"
    return 1
  fi

  if ! mkdir -p "$dst_dir" 2>/dev/null; then
    tgdb_warn "無法建立 Quadlet 使用者目錄：$dst_dir（略過同步）。"
    return 1
  fi

  _kopia_clear_user_quadlet_units || true

  if ! _kopia_restore_runtime_quadlet_tree "$src_dir"; then
    tgdb_warn "同步 Quadlet runtime 失敗：$src_dir -> $dst_dir"
    return 1
  fi

  echo "✅ 已同步 Quadlet runtime：$src_dir -> $dst_dir"
  return 0
}
