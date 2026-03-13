#!/bin/bash

# Kopia 備份：目錄準備與 DB 還原助手
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_BACKUP_PREPARE_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_BACKUP_PREPARE_LOADED=1

_kopia_prepare_db_data_dirs() {
  local -A seen=()
  local path
  local total=0 created=0 failed=0

  while IFS= read -r path; do
    [ -n "${path:-}" ] || continue
    if [ -n "${seen["$path"]+x}" ]; then
      continue
    fi
    seen["$path"]=1
    total=$((total + 1))

    if [ -d "$path" ]; then
      continue
    fi

    if mkdir -p "$path" 2>/dev/null; then
      created=$((created + 1))
    else
      failed=$((failed + 1))
      tgdb_warn "無法建立 DB data 目錄：$path"
    fi
  done < <(_kopia_collect_db_data_dirs)

  if [ "$total" -gt 0 ]; then
    echo "ℹ️ DB data 目錄檢查：總數=$total / 新建=$created / 失敗=$failed"
  fi

  [ "$failed" -eq 0 ] && return 0
  return 1
}

_kopia_collect_nginx_cache_dirs() {
  # 輸出：每行一個「host 絕對路徑」的 Nginx cache dir
  local file host_path
  while IFS= read -r file; do
    [ -f "$file" ] || continue

    if _kopia_unit_has_label "$file" "app=nginx"; then
      host_path="$(_kopia_unit_volume_host_for_container_path "$file" "/var/cache/nginx" 2>/dev/null || true)"
      [ -n "${host_path:-}" ] && printf '%s\n' "$host_path"

      host_path="$(_kopia_unit_volume_host_for_container_path "$file" "/cache" 2>/dev/null || true)"
      [ -n "${host_path:-}" ] && printf '%s\n' "$host_path"
    fi
  done < <(_kopia_scan_container_units)
}

_kopia_prepare_nginx_cache_dirs() {
  local -A seen=()
  local path
  local total=0 created=0 failed=0

  while IFS= read -r path; do
    [ -n "${path:-}" ] || continue
    if [ -n "${seen["$path"]+x}" ]; then
      continue
    fi
    seen["$path"]=1
    total=$((total + 1))

    if [ -d "$path" ]; then
      continue
    fi

    if mkdir -p "$path" 2>/dev/null; then
      created=$((created + 1))
    else
      failed=$((failed + 1))
      tgdb_warn "無法建立 Nginx cache 目錄：$path"
    fi
  done < <(_kopia_collect_nginx_cache_dirs)

  if [ "$total" -gt 0 ]; then
    echo "ℹ️ Nginx cache 目錄檢查：總數=$total / 新建=$created / 失敗=$failed"
  fi

  [ "$failed" -eq 0 ] && return 0
  return 1
}

_kopia_restore_db_from_dumps() {
  local script="$KOPIA_DIR/dbadmin/dbbackup-cli.sh"
  if [ ! -f "$script" ]; then
    tgdb_warn "找不到 DB 批次腳本：$script（略過 DB 還原）。"
    return 1
  fi

  echo "⏳ 正在執行 DB 恢復（latest db-dump）..."
  local out rc=0
  out="$(TGDB_DBBACKUP_NONINTERACTIVE=1 bash "$script" import-all-latest 2>&1)" || rc=$?
  if [ -n "${out:-}" ]; then
    printf '%s\n' "$out"
  fi
  if [ "$rc" -ne 0 ]; then
    tgdb_warn "DB 恢復流程有錯誤（rc=$rc），請檢查上方輸出。"
    return "$rc"
  fi

  echo "✅ DB 恢復流程完成。"
  return 0
}
