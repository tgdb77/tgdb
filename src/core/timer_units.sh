#!/bin/bash

# TGDB user systemd timer/service 單元管理
# 用途：
# - 將 TGDB 管理的定時任務單元暫存到持久化 config/timer
# - 還原時先清理既有 user units，再回填並重新啟用 timers
# 注意：此檔案為 library，會被共用模組 source，請勿在此更改 shell options。

if [ -n "${_TGDB_CORE_TIMER_UNITS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_TIMER_UNITS_LOADED=1

_tgdb_timer_units_systemctl_user_try() {
  if declare -F _systemctl_user_try >/dev/null 2>&1; then
    _systemctl_user_try "$@"
    return $?
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    return 127
  fi

  systemctl --user "$@"
}

_tgdb_timer_units_collect_from_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0

  find "$dir" -maxdepth 1 -type f \
    \( -name 'tgdb-*.timer' -o -name 'tgdb-*.service' \) \
    -printf '%f\n' 2>/dev/null | LC_ALL=C sort -u
}

tgdb_timer_units_stage_to_persist() {
  local src_dir dest_dir persist_cfg_dir
  src_dir="$(rm_user_systemd_dir)"
  dest_dir="$(rm_persist_timer_dir)"
  persist_cfg_dir="$(rm_persist_config_dir)" || return 1

  mkdir -p "$persist_cfg_dir" 2>/dev/null || true

  local -a unit_files=()
  mapfile -t unit_files < <(_tgdb_timer_units_collect_from_dir "$src_dir")

  if [ ${#unit_files[@]} -eq 0 ]; then
    rm -rf -- "$dest_dir" 2>/dev/null || true
    return 0
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d "$persist_cfg_dir/.timer.tmp.XXXXXX" 2>/dev/null || true)"
  if [ -z "${tmp_dir:-}" ] || [ ! -d "$tmp_dir" ]; then
    tgdb_warn "無法建立定時任務單元暫存目錄（略過同步）：$persist_cfg_dir"
    return 1
  fi

  local unit copy_failed=0
  for unit in "${unit_files[@]}"; do
    if ! cp -a "$src_dir/$unit" "$tmp_dir/$unit" 2>/dev/null; then
      copy_failed=1
      break
    fi
  done

  if [ "$copy_failed" -ne 0 ]; then
    rm -rf -- "$tmp_dir" 2>/dev/null || true
    tgdb_warn "同步定時任務單元失敗（已略過）：$src_dir -> $dest_dir"
    return 1
  fi

  rm -rf -- "$dest_dir" 2>/dev/null || true
  if ! mv -f "$tmp_dir" "$dest_dir" 2>/dev/null; then
    rm -rf -- "$tmp_dir" 2>/dev/null || true
    tgdb_warn "同步定時任務單元失敗（無法原子改名，已略過）：$tmp_dir -> $dest_dir"
    return 1
  fi

  return 0
}

tgdb_timer_units_clear_user() {
  local dst_dir
  dst_dir="$(rm_user_systemd_dir)"
  [ -d "$dst_dir" ] || return 0

  local -a unit_files=()
  mapfile -t unit_files < <(_tgdb_timer_units_collect_from_dir "$dst_dir")
  [ ${#unit_files[@]} -gt 0 ] || return 0

  if command -v systemctl >/dev/null 2>&1; then
    _tgdb_timer_units_systemctl_user_try daemon-reload >/dev/null 2>&1 || true
    local unit
    for unit in "${unit_files[@]}"; do
      _tgdb_timer_units_systemctl_user_try disable --now -- "$unit" >/dev/null 2>&1 || true
    done
  fi

  local removed=0 failed=0
  local f
  for f in "${unit_files[@]}"; do
    if rm -f -- "$dst_dir/$f" 2>/dev/null; then
      removed=$((removed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  if [ "$failed" -gt 0 ]; then
    tgdb_warn "清理既有定時任務單元時有失敗（成功=$removed / 失敗=$failed）：$dst_dir"
    return 1
  fi

  echo "ℹ️ 已清理既有定時任務單元：$dst_dir（共 $removed 個）"
  return 0
}

tgdb_timer_units_sync_persist_to_user() {
  local src_dir dst_dir
  src_dir="$(rm_persist_timer_dir)"
  dst_dir="$(rm_user_systemd_dir)"

  if [ ! -d "$src_dir" ]; then
    tgdb_warn "未找到定時任務單元備份目錄：$src_dir（略過同步）。"
    return 1
  fi

  if ! mkdir -p "$dst_dir" 2>/dev/null; then
    tgdb_warn "無法建立 user systemd 目錄：$dst_dir（略過同步）。"
    return 1
  fi

  tgdb_timer_units_clear_user || true

  if ! cp -a "$src_dir/." "$dst_dir/"; then
    tgdb_warn "同步定時任務單元失敗：$src_dir -> $dst_dir"
    return 1
  fi

  echo "✅ 已同步定時任務單元：$src_dir -> $dst_dir"
  return 0
}

tgdb_timer_units_enable_all_user() {
  local dst_dir
  dst_dir="$(rm_user_systemd_dir)"
  [ -d "$dst_dir" ] || return 0

  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi

  _tgdb_timer_units_systemctl_user_try daemon-reload >/dev/null 2>&1 || true

  local -a timer_units=()
  mapfile -t timer_units < <(find "$dst_dir" -maxdepth 1 -type f -name 'tgdb-*.timer' -printf '%f\n' 2>/dev/null | LC_ALL=C sort -u)
  [ ${#timer_units[@]} -gt 0 ] || return 0

  local unit rc=0
  for unit in "${timer_units[@]}"; do
    if ! _tgdb_timer_units_systemctl_user_try enable --now -- "$unit" >/dev/null 2>&1; then
      tgdb_warn "啟用定時任務單元失敗：$unit"
      rc=1
    fi
  done

  return "$rc"
}
