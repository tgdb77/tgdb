#!/bin/bash

# Kopia 備份：快照還原輔助函式
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_BACKUP_RESTORE_LIB_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_BACKUP_RESTORE_LIB_LOADED=1

_kopia_snapshot_list_text() {
  local name="${1:-kopia}"
  # 重部署後容器 hostname 可能變更，且 --all 搭配 <source> 在部分版本可能回空；
  # 統一先抓全量清單，再由本地邏輯按 source path 過濾。
  _kopia_exec "$name" kopia snapshot list --all
}

_kopia_snapshot_rows_for_source_from_all_text() {
  local source_path="${1:-}"
  [ -n "${source_path:-}" ] || return 1

  local line id current_source=""
  local -A seen=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^[^[:space:]]+@[^[:space:]]+:(/.*)$ ]]; then
      current_source="${BASH_REMATCH[1]}"
      continue
    fi

    [ "${current_source:-}" = "$source_path" ] || continue
    id="$(printf '%s\n' "$line" | grep -Eo 'k[0-9a-f]{20,}' | head -n1 || true)"
    [ -n "${id:-}" ] || continue

    if [ -z "${seen["$id"]+x}" ]; then
      seen["$id"]=1
      printf '%s\t%s\n' "$id" "$line"
    fi
  done
}

_kopia_snapshot_ids_for_source_from_all_text() {
  local source_path="${1:-}"
  [ -n "${source_path:-}" ] || return 1
  _kopia_snapshot_rows_for_source_from_all_text "$source_path" | cut -f1
}

_kopia_snapshot_preview() {
  local name="${1:-kopia}" snapshot_id="${2:-}" label="${3:-snapshot}"
  [ -n "${snapshot_id:-}" ] || return 1

  echo "[$label] snapshot=$snapshot_id"
  local list_out list_rc=0
  list_out="$(_kopia_exec "$name" kopia list -l "$snapshot_id" 2>&1)" || list_rc=$?
  if [ "$list_rc" -eq 0 ]; then
    echo "----- 組成預覽（前 120 行） -----"
    printf '%s\n' "$list_out" | sed -n '1,120p'
  else
    echo "（無法取得清單預覽）"
    if [ -n "${list_out:-}" ]; then
      printf '%s\n' "$list_out" | sed -n '1,20p'
    fi
  fi

  if [ "$list_rc" -ne 0 ]; then
    return 1
  fi
  return 0
}

_kopia_diff_dry_run_report() {
  local src_dir="$1" dst_dir="$2" label="$3"
  if [ ! -d "$src_dir" ]; then
    tgdb_fail "dry-run 來源不存在（$label）：$src_dir" 1 || true
    return 1
  fi
  mkdir -p "$dst_dir" 2>/dev/null || true

  local out rc=0
  out="$(diff -qr --no-dereference "$src_dir" "$dst_dir" 2>&1)" || rc=$?
  if [ "$rc" -gt 1 ]; then
    tgdb_fail "dry-run 失敗（$label）：$out" 1 || true
    return "$rc"
  fi

  local filtered=""
  if [ "$rc" -eq 1 ]; then
    filtered="$(printf '%s\n' "$out" | sed '/^$/d' || true)"
  fi

  # 預覽降噪：避免 Kopia 自身 cache/log 與備份狀態檔淹沒重點差異。
  local filtered_view
  filtered_view="$(printf '%s\n' "$filtered" | awk -v src="$src_dir" -v dst="$dst_dir" '
    {
      line=$0
      l=line
      gsub(src, "", l)
      gsub(dst, "", l)

      if (l ~ /\/kopia\/cache(\/|:)/) next
      if (l ~ /\/kopia\/logs(\/|:)/) next
      if (line ~ /backup\/kopia_status\.conf/) next

      print line
    }
  ' || true)"

  local total_changes added_changes deleted_changes modified_changes type_changes other_changes
  if [ -n "${filtered_view:-}" ]; then
    local stats
    stats="$(printf '%s\n' "$filtered_view" | awk -v s="Only in $src_dir:" -v d="Only in $dst_dir:" '
      {
        total++
        if (index($0, s)==1) {add++; next}
        if (index($0, d)==1) {del++; next}
        if ($0 ~ /^Files .* and .* differ$/) {mod++; next}
        if ($0 ~ /^Symbolic links .* and .* differ$/) {mod++; next}
        if ($0 ~ /^File .* is a .* while file .* is a .*$/) {type++; next}
        other++
      }
      END {
        printf "%d\t%d\t%d\t%d\t%d\t%d", total+0, add+0, del+0, mod+0, type+0, other+0
      }
    ')"
    IFS=$'\t' read -r total_changes added_changes deleted_changes modified_changes type_changes other_changes <<< "$stats"
  else
    total_changes="0"
    added_changes="0"
    deleted_changes="0"
    modified_changes="0"
    type_changes="0"
    other_changes="0"
  fi

  echo "[$label] 變更項目：$total_changes，新增：$added_changes，刪除：$deleted_changes，修改：$modified_changes，型別變更：$type_changes，其他：$other_changes"
  if [ "$total_changes" -gt 0 ]; then
    printf '%s\n' "$filtered_view" | sed -n '1,120p'
    if [ "$total_changes" -gt 120 ]; then
      echo "...（其餘省略）"
    fi
  fi
  return 0
}

_kopia_copy_replace_apply() {
  local src_dir="$1" dst_dir="$2" label="$3"
  if [ ! -d "$src_dir" ]; then
    tgdb_fail "正式還原來源不存在（$label）：$src_dir" 1 || true
    return 1
  fi

  local dst_parent dst_name tmp_dir base_ts retry
  dst_parent="$(dirname "$dst_dir")"
  dst_name="$(basename "$dst_dir")"
  mkdir -p "$dst_parent" 2>/dev/null || {
    tgdb_fail "無法建立目標父目錄（$label）：$dst_parent" 1 || true
    return 1
  }

  base_ts="$(date +%s)"
  retry=0
  tmp_dir="$dst_parent/.kopia-restore.${dst_name}.tmp.${base_ts}.$$"
  while [ -e "$tmp_dir" ]; do
    retry=$((retry + 1))
    tmp_dir="$dst_parent/.kopia-restore.${dst_name}.tmp.${base_ts}.$$.$retry"
  done

  if ! mkdir -p "$tmp_dir" 2>/dev/null; then
    tgdb_fail "無法建立暫存替換目錄（$label）：$tmp_dir" 1 || true
    return 1
  fi

  if ! cp -a "$src_dir/." "$tmp_dir/" 2>/dev/null; then
    rm -rf "$tmp_dir" 2>/dev/null || true
    tgdb_fail "複製暫存資料失敗（$label）：$src_dir -> $tmp_dir" 1 || true
    return 1
  fi

  if [ -e "$dst_dir" ] || [ -L "$dst_dir" ]; then
    if ! rm -rf -- "$dst_dir" 2>/dev/null; then
      rm -rf "$tmp_dir" 2>/dev/null || true
      tgdb_fail "清除既有目標失敗（$label）：$dst_dir" 1 || true
      return 1
    fi
  fi

  if ! mv -f "$tmp_dir" "$dst_dir" 2>/dev/null; then
    rm -rf "$tmp_dir" 2>/dev/null || true
    tgdb_fail "替換目標目錄失敗（$label）：$dst_dir" 1 || true
    return 1
  fi
  return 0
}

_kopia_reload_server() {
  local name="${1:-kopia}"

  if command -v systemctl >/dev/null 2>&1; then
    _systemctl_user_try restart -- "${name}.service" "container-${name}.service" >/dev/null 2>&1 || true
  fi

  if ! podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
    podman restart "$name" >/dev/null 2>&1 || podman start "$name" >/dev/null 2>&1 || true
  fi

  _kopia_ensure_container_running "$name" || return 1
  _kopia_wait_exec_ready "$name" || return 1
  return 0
}
