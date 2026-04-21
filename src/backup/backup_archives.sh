#!/bin/bash

# 全系統備份：備份檔與目錄管理
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_BACKUP_ARCHIVES_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_ARCHIVES_LOADED=1

_backup_ensure_dirs() {
    mkdir -p "$BACKUP_ROOT"
    if [ ! -d "$TGDB_DIR" ]; then
        local msg
        printf -v msg '%s\n%s' \
          "找不到 TGDB 目錄：$TGDB_DIR" \
          "請先完成 TGDB 初始化後再執行備份。"
        tgdb_fail "$msg" 1 || return $?
    fi
    local tgdb_parent
    tgdb_parent="$(dirname "$TGDB_DIR")"
    if [ "$tgdb_parent" != "$BACKUP_ROOT" ]; then
        local msg
        printf -v msg '%s\n%s' \
          "TGDB_DIR ($TGDB_DIR) 不在備份根目錄 ($BACKUP_ROOT) 底下。" \
          "請將 TGDB_BACKUP_ROOT 設為：$tgdb_parent 或調整 TGDB_DIR 設定。"
        tgdb_fail "$msg" 1 || return $?
    fi

    # 與 record_manager 的規範對齊：持久化設定目錄應位於 $BACKUP_ROOT/config
    # 避免還原/備份時寫入錯誤目的地（例如 PERSIST_CONFIG_DIR 與 TGDB_DIR 分離）。
    local persist_cfg_dir expected_cfg_dir
    persist_cfg_dir="$(rm_persist_config_dir)" || return 1
    expected_cfg_dir="$BACKUP_ROOT/config"
    if [ "$persist_cfg_dir" != "$expected_cfg_dir" ]; then
        local msg
        printf -v msg '%s\n%s\n%s\n%s' \
          "偵測到持久化設定目錄位置不一致，為避免備份/還原落在錯誤目錄已中止。" \
          " - 目前 rm_persist_config_dir: $persist_cfg_dir" \
          " - 備份根目錄預期 config:  $expected_cfg_dir" \
          "請調整 PERSIST_CONFIG_DIR 或 TGDB_DIR/TGDB_BACKUP_ROOT，讓它們位於同一持久化根目錄。"
        tgdb_fail "$msg" 1 || return $?
    fi

    mkdir -p "$BACKUP_DIR"
    _backup_ensure_module_config
}

_backup_list_backups_newest_first() {
    ls -1t "$BACKUP_DIR/${BACKUP_PREFIX}-"*.tar.gz 2>/dev/null || true
}

_backup_list_archives_by_prefix_newest_first() {
    local prefix="$1"
    [ -n "${prefix:-}" ] || return 0
    ls -1t "$BACKUP_DIR/${prefix}-"*.tar.gz 2>/dev/null || true
}

_backup_get_latest_backup() {
    local latest
    latest=$(_backup_list_backups_newest_first | head -n1 || true)
    if [ -z "$latest" ]; then
        return 1
    fi
    # shellcheck disable=SC2034 # 供其他互動流程讀取最新備份路徑
    LATEST_BACKUP="$latest"
    return 0
}

_backup_cleanup_old_by_prefix() {
    local prefix="$1"
    local max_count="$2"
    local files=()
    mapfile -t files < <(_backup_list_archives_by_prefix_newest_first "$prefix")
    local count=${#files[@]}
    if [ "$count" -le "$max_count" ]; then
        return 0
    fi

    local i
    for ((i = max_count; i < count; i++)); do
        local f="${files[$i]}"
        [ -f "$f" ] || continue
        echo "🗑️ 移除舊備份：$f"
        rm -f -- "$f" || true
    done
}

_backup_cleanup_old() {
    _backup_cleanup_old_by_prefix "$BACKUP_PREFIX" "$(_backup_full_max_count_get)"
}

_backup_list_all_managed_archives_newest_first() {
    [ -d "$BACKUP_DIR" ] || return 0
    find "$BACKUP_DIR" -maxdepth 1 -type f \
      \( -name "${BACKUP_PREFIX}-*.tar.gz" -o -name "${BACKUP_SELECT_PREFIX}-*.tar.gz" \) \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-
}

_backup_archive_kind() {
    local archive="$1"
    local base
    base="$(basename "$archive")"
    case "$base" in
      ${BACKUP_SELECT_PREFIX}-*.tar.gz) printf '%s\n' "select" ;;
      ${BACKUP_PREFIX}-*.tar.gz) printf '%s\n' "full" ;;
      *) printf '%s\n' "unknown" ;;
    esac
}

_backup_archive_kind_label() {
    local kind="$1"
    case "$kind" in
      select) printf '%s\n' "指定備份" ;;
      full) printf '%s\n' "全備份" ;;
      *) printf '%s\n' "未知" ;;
    esac
}

_backup_archive_time_display() {
    local archive="$1"
    stat -c %y "$archive" 2>/dev/null | cut -d'.' -f1
}

_backup_archive_size_display() {
    local archive="$1"
    du -h "$archive" 2>/dev/null | cut -f1
}

_backup_archive_instance_names() {
    local archive="$1"
    local tgdb_name
    tgdb_name="$(basename "$TGDB_DIR")"
    tar -tzf "$archive" 2>/dev/null | awk -F/ -v app="$tgdb_name" '
      $1 == app && NF >= 3 && $3 == ".tgdb_instance_meta" && $2 != "" { print $2 }
    ' | LC_ALL=C sort -u
}

_backup_archive_instance_summary() {
    local archive="$1"
    local -a names=()
    local n joined=""
    while IFS= read -r n; do
      [ -n "$n" ] && names+=("$n")
    done < <(_backup_archive_instance_names "$archive")

    if [ ${#names[@]} -eq 0 ]; then
      printf '%s\n' "-"
      return 0
    fi

    local i limit=3
    for ((i = 0; i < ${#names[@]} && i < limit; i++)); do
      joined+="${joined:+, }${names[$i]}"
    done
    if [ ${#names[@]} -gt "$limit" ]; then
      joined+="…（共 ${#names[@]} 個）"
    fi
    printf '%s\n' "$joined"
}

_backup_print_managed_archives() {
    local -a archives=()
    local archive
    while IFS= read -r archive; do
      [ -n "$archive" ] && archives+=("$archive")
    done < <(_backup_list_all_managed_archives_newest_first)

    if [ ${#archives[@]} -eq 0 ]; then
      echo "目前尚無任何 TGDB 備份檔。"
      return 1
    fi

    local idx kind label time_str size_str summary
    for ((idx = 0; idx < ${#archives[@]}; idx++)); do
      archive="${archives[$idx]}"
      kind="$(_backup_archive_kind "$archive")"
      label="$(_backup_archive_kind_label "$kind")"
      time_str="$(_backup_archive_time_display "$archive" 2>/dev/null || echo "-")"
      size_str="$(_backup_archive_size_display "$archive" 2>/dev/null || echo "-")"
      summary="$(_backup_archive_instance_summary "$archive" 2>/dev/null || echo "-")"
      printf '%2d. [%s] %s\n' "$((idx + 1))" "$label" "$(basename "$archive")"
      echo "    時間: $time_str | 大小: $size_str | 實例: $summary"
    done
    return 0
}
