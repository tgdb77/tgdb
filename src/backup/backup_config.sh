#!/bin/bash

# 全系統備份：設定與 Rclone 相關函式
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_BACKUP_CONFIG_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_CONFIG_LOADED=1

_backup_ensure_module_config() {
  mkdir -p "$BACKUP_MODULE_DIR" 2>/dev/null || true
  [ -f "$BACKUP_MODULE_CONFIG_FILE" ] || touch "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null || true
}

_backup_rclone_remote_get() {
  _backup_ensure_module_config
  _read_kv_or_default "rclone_remote" "$BACKUP_MODULE_CONFIG_FILE" ""
}

_backup_rclone_remote_set() {
  local remote="$1"
  _backup_ensure_module_config

  if grep -q '^rclone_remote=' "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^rclone_remote=.*$|rclone_remote=$remote|" "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null || true
  else
    printf 'rclone_remote=%s\n' "$remote" >>"$BACKUP_MODULE_CONFIG_FILE"
  fi
}

_backup_rclone_remote_disable() {
  _backup_ensure_module_config
  sed -i '/^rclone_remote=/d' "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null || true
}

_backup_select_targets_get() {
  _backup_ensure_module_config
  _read_kv_or_default "selected_backup_instances" "$BACKUP_MODULE_CONFIG_FILE" ""
}

_backup_select_targets_set() {
  local targets="$1"
  _backup_ensure_module_config

  if grep -q '^selected_backup_instances=' "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^selected_backup_instances=.*$|selected_backup_instances=$targets|" "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null || true
  else
    printf 'selected_backup_instances=%s\n' "$targets" >>"$BACKUP_MODULE_CONFIG_FILE"
  fi
}

_backup_select_targets_disable() {
  _backup_ensure_module_config
  sed -i '/^selected_backup_instances=/d' "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null || true
}

_backup_full_max_count_get() {
  _backup_ensure_module_config
  local v
  v="$(_read_kv_or_default "backup_max_count" "$BACKUP_MODULE_CONFIG_FILE" "$BACKUP_MAX_COUNT")"
  if [[ "$v" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$v"
  else
    printf '%s\n' "$BACKUP_MAX_COUNT"
  fi
}

_backup_full_max_count_set() {
  local count="$1"
  _backup_ensure_module_config
  if grep -q '^backup_max_count=' "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^backup_max_count=.*$|backup_max_count=$count|" "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null || true
  else
    printf 'backup_max_count=%s\n' "$count" >>"$BACKUP_MODULE_CONFIG_FILE"
  fi
}

_backup_select_max_count_get() {
  _backup_ensure_module_config
  local v
  v="$(_read_kv_or_default "backup_select_max_count" "$BACKUP_MODULE_CONFIG_FILE" "$BACKUP_SELECT_MAX_COUNT")"
  if [[ "$v" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$v"
  else
    printf '%s\n' "$BACKUP_SELECT_MAX_COUNT"
  fi
}

_backup_select_max_count_set() {
  local count="$1"
  _backup_ensure_module_config
  if grep -q '^backup_select_max_count=' "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^backup_select_max_count=.*$|backup_select_max_count=$count|" "$BACKUP_MODULE_CONFIG_FILE" 2>/dev/null || true
  else
    printf 'backup_select_max_count=%s\n' "$count" >>"$BACKUP_MODULE_CONFIG_FILE"
  fi
}

_backup_select_targets_to_array() {
  local raw="${1:-}"
  local out_var="$2"
  # shellcheck disable=SC2178
  local -n out_ref="$out_var"
  out_ref=()

  [ -n "${raw:-}" ] || return 0
  local token
  for token in $raw; do
    [ -n "$token" ] && out_ref+=("$token")
  done
}

_backup_rclone_sync_to_remote() {
  local remote
  remote="$(_backup_rclone_remote_get)"
  if [ -z "${remote:-}" ]; then
    return 0
  fi

  if ! command -v rclone >/dev/null 2>&1; then
    tgdb_warn "已設定 Rclone 遠端，但找不到 rclone 指令，略過遠端同步。"
    return 1
  fi

  local remote_base="${remote%:}"
  if [ -z "$remote_base" ]; then
    tgdb_warn "Rclone 遠端名稱不合法：$remote"
    return 1
  fi
  local dest="${remote_base}:tgdb-backup"

  echo "☁️ 正在同步備份到 Rclone 遠端：$dest"
  echo "   - 來源：$BACKUP_DIR"
  echo "   - 目的：$dest"

  # 使用 sync 讓遠端與本地備份目錄保持一致（配合 BACKUP_MAX_COUNT）
  if rclone sync "$BACKUP_DIR" "$dest" --create-empty-src-dirs; then
    echo "✅ Rclone 同步完成：$dest"
    return 0
  fi

  tgdb_warn "Rclone 同步失敗：$dest（本地備份仍已完成）"
  return 1
}

_backup_rclone_backup_remote_path() {
  local remote
  remote="$(_backup_rclone_remote_get)"
  if [ -z "${remote:-}" ]; then
    return 1
  fi

  local remote_base="${remote%:}"
  if [ -z "$remote_base" ]; then
    return 1
  fi

  printf '%s\n' "${remote_base}:tgdb-backup"
}

_backup_list_remote_archives_newest_first() {
  if ! command -v rclone >/dev/null 2>&1; then
    return 1
  fi

  local src
  src="$(_backup_rclone_backup_remote_path)" || return 1

  rclone lsf "$src" --files-only 2>/dev/null | awk '
    /^tgdb-backup-[0-9]{8}-[0-9]{6}\.tar\.gz$/ { print; next }
    /^tgdb-backup-select-[0-9]{8}-[0-9]{6}\.tar\.gz$/ { print; next }
  ' | LC_ALL=C sort -r
}

_backup_rclone_restore_selected_to_local() {
  if ! command -v rclone >/dev/null 2>&1; then
    tgdb_fail "找不到 rclone 指令，無法從遠端還原備份。" 1 || return $?
  fi

  local src_root
  src_root="$(_backup_rclone_backup_remote_path)" || {
    tgdb_fail "尚未設定可用的 Rclone 遠端，無法從遠端還原備份。" 1 || return $?
  }

  mkdir -p "$BACKUP_DIR" 2>/dev/null || true

  local ok=0 fail=0 name
  for name in "$@"; do
    [ -n "$name" ] || continue
    echo "☁️ 正在拉回：$name"
    if rclone copyto "$src_root/$name" "$BACKUP_DIR/$name"; then
      echo "✅ 已拉回：$name"
      ok=$((ok + 1))
    else
      tgdb_warn "拉回失敗：$name"
      fail=$((fail + 1))
    fi
  done

  echo "結果：成功=$ok / 失敗=$fail"
  if [ "$fail" -eq 0 ]; then
    return 0
  fi

  return 1
}

