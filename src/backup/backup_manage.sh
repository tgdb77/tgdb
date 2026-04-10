#!/bin/bash

# 全系統備份：備份檔管理互動流程
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_BACKUP_MANAGE_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_MANAGE_LOADED=1

backup_retention_config_interactive() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    local cur_full cur_select new_full new_select
    cur_full="$(_backup_full_max_count_get)"
    cur_select="$(_backup_select_max_count_get)"

    echo "目前保留數量設定："
    echo " - 全備份：$cur_full"
    echo " - 指定備份：$cur_select"
    echo ""

    while true; do
        read -r -e -p "輸入全備份保留數量（正整數，預設 $cur_full）: " new_full
        new_full="${new_full:-$cur_full}"
        if [[ "$new_full" =~ ^[1-9][0-9]*$ ]]; then
            break
        fi
        tgdb_err "請輸入正整數。"
    done

    while true; do
        read -r -e -p "輸入指定備份保留數量（正整數，預設 $cur_select）: " new_select
        new_select="${new_select:-$cur_select}"
        if [[ "$new_select" =~ ^[1-9][0-9]*$ ]]; then
            break
        fi
        tgdb_err "請輸入正整數。"
    done

    _backup_full_max_count_set "$new_full"
    _backup_select_max_count_set "$new_select"
    echo "✅ 已更新保留數量：全備份=$new_full / 指定備份=$new_select"
    echo "ℹ️ 新設定會在之後建立新備份時套用。"
}

backup_delete_selected_archives_interactive() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    local -a archives=()
    local archive
    while IFS= read -r archive; do
        [ -n "$archive" ] && archives+=("$archive")
    done < <(_backup_list_all_managed_archives_newest_first)

    if [ ${#archives[@]} -eq 0 ]; then
        tgdb_err "目前尚無任何 TGDB 備份檔。"
        ui_pause
        return 1
    fi

    echo "目前可刪除的備份："
    _backup_print_managed_archives
    echo "----------------------------------"
    echo "提示：可多選，支援空白 / 逗號 / 範圍，例如：1 3 5-7"

    local pick_raw
    while true; do
        read -r -e -p "請輸入要刪除的備份序號（輸入 0 取消）: " pick_raw
        pick_raw="${pick_raw//[$'\t\r\n']/ }"
        pick_raw="${pick_raw#"${pick_raw%%[![:space:]]*}"}"
        pick_raw="${pick_raw%"${pick_raw##*[![:space:]]}"}"
        if [ "$pick_raw" = "0" ] || [ -z "$pick_raw" ]; then
            echo "操作已取消。"
            ui_pause
            return 0
        fi
        if _backup_parse_multi_selection "$pick_raw" "${#archives[@]}"; then
            break
        fi
        tgdb_err "輸入格式不正確，請輸入有效序號、逗號或範圍。"
    done

    local -a targets=()
    local idx
    for idx in "${BACKUP_SELECTED_INSTANCES[@]}"; do
        targets+=("${archives[$((idx - 1))]}")
    done

    echo "將刪除以下備份："
    for archive in "${targets[@]}"; do
        echo " - $(basename "$archive")"
    done

    if ! ui_confirm_yn "確認刪除嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消。"
        ui_pause
        return 0
    fi

    local ok=0 fail=0
    for archive in "${targets[@]}"; do
        if rm -f -- "$archive"; then
            echo "✅ 已刪除：$(basename "$archive")"
            ok=$((ok + 1))
        else
            tgdb_warn "刪除失敗：$(basename "$archive")"
            fail=$((fail + 1))
        fi
    done

    echo "結果：成功=$ok / 失敗=$fail"
    ui_pause
    [ "$fail" -eq 0 ]
}

backup_restore_archive_interactive() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    local -a archives=()
    local archive
    while IFS= read -r archive; do
        [ -n "$archive" ] && archives+=("$archive")
    done < <(_backup_list_all_managed_archives_newest_first)

    if [ ${#archives[@]} -eq 0 ]; then
        tgdb_err "目前尚無任何 TGDB 備份檔。"
        ui_pause
        return 1
    fi

    echo "可恢復的備份："
    _backup_print_managed_archives
    echo "----------------------------------"

    local choice
    if ! ui_prompt_index choice "請輸入要恢復的備份序號（輸入 0 取消）: " 1 "${#archives[@]}" "" 0; then
        echo "操作已取消。"
        ui_pause
        return 0
    fi

    archive="${archives[$((choice - 1))]}"
    local kind kind_label
    kind="$(_backup_archive_kind "$archive")"
    kind_label="$(_backup_archive_kind_label "$kind")"

    echo "將恢復：$(basename "$archive")"
    echo "類型：$kind_label"

    if [ "$kind" = "full" ]; then
        echo "⚠️ 此動作會覆蓋整體 TGDB 設定層與相關單元。"
        if ! ui_confirm_yn "確認繼續嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            echo "操作已取消。"
            ui_pause
            return 0
        fi
        if _backup_restore_from_archive "$archive"; then
            echo "✅ 已還原全備份：$(basename "$archive")"
        else
            tgdb_err "還原失敗：$(basename "$archive")"
            ui_pause
            return 1
        fi
        ui_pause
        return 0
    fi

    if [ "$kind" = "select" ]; then
        local -a names=()
        local n ok=0 fail=0
        while IFS= read -r n; do
            [ -n "$n" ] && names+=("$n")
        done < <(_backup_archive_instance_names "$archive")

        if [ ${#names[@]} -eq 0 ]; then
            tgdb_err "此指定備份中找不到任何可還原的實例。"
            ui_pause
            return 1
        fi

        echo "將恢復以下實例："
        for n in "${names[@]}"; do
            echo " - $n"
        done

        if ! ui_confirm_yn "確認繼續嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            echo "操作已取消。"
            ui_pause
            return 0
        fi

        for n in "${names[@]}"; do
            if _backup_restore_selected_instance_from_archive "$archive" "$n"; then
                echo "✅ 已還原指定實例：$n"
                ok=$((ok + 1))
            else
                tgdb_warn "指定實例還原失敗：$n"
                fail=$((fail + 1))
            fi
        done

        echo "結果：成功=$ok / 失敗=$fail"
        ui_pause
        [ "$fail" -eq 0 ]
        return $?
    fi

    tgdb_err "無法辨識的備份類型：$(basename "$archive")"
    ui_pause
    return 1
}

backup_rclone_restore_to_local_interactive() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    local remote
    remote="$(_backup_rclone_remote_get 2>/dev/null || true)"
    if [ -z "${remote:-}" ]; then
        tgdb_err "尚未設定 Rclone 遠端，請先到自動備份設定中開啟遠端同步。"
        ui_pause
        return 1
    fi

    if ! command -v rclone >/dev/null 2>&1; then
        tgdb_err "找不到 rclone 指令，無法從遠端還原備份。"
        ui_pause
        return 1
    fi

    echo "目前遠端：${remote%:}:tgdb-backup"
    echo "本機目錄：$BACKUP_DIR"
    echo "⚠️ 此動作會以遠端同名檔案覆蓋本機既有備份。"
    echo "⚠️ 本機額外存在、但遠端沒有的備份檔不會被刪除。"
    echo "----------------------------------"

    local -a archives=()
    local archive
    while IFS= read -r archive; do
        [ -n "$archive" ] && archives+=("$archive")
    done < <(_backup_list_remote_archives_newest_first)

    if [ ${#archives[@]} -eq 0 ]; then
        tgdb_err "遠端目前沒有可拉回的 TGDB 備份。"
        ui_pause
        return 1
    fi

    echo "遠端可用備份："
    local i local_mark
    for ((i = 0; i < ${#archives[@]}; i++)); do
        local_mark=""
        if [ -f "$BACKUP_DIR/${archives[$i]}" ]; then
            local_mark="（本機已有同名檔，拉回會覆蓋）"
        fi
        printf '%2d. %s %s\n' "$((i + 1))" "${archives[$i]}" "$local_mark"
    done
    echo "----------------------------------"
    echo "提示：可多選，支援空白 / 逗號 / 範圍，例如：1 3 5-7"
    echo "提示：輸入 A 代表全部拉回"

    local pick_raw
    while true; do
        read -r -e -p "請輸入要拉回的備份序號（輸入 0 取消）: " pick_raw
        pick_raw="${pick_raw//[$'\t\r\n']/ }"
        pick_raw="${pick_raw#"${pick_raw%%[![:space:]]*}"}"
        pick_raw="${pick_raw%"${pick_raw##*[![:space:]]}"}"

        case "${pick_raw,,}" in
            0|"")
                echo "操作已取消。"
                ui_pause
                return 0
                ;;
            a|all|"*")
                BACKUP_SELECTED_INSTANCES=()
                for ((i = 1; i <= ${#archives[@]}; i++)); do
                    BACKUP_SELECTED_INSTANCES+=("$i")
                done
                break
                ;;
        esac

        if _backup_parse_multi_selection "$pick_raw" "${#archives[@]}"; then
            break
        fi
        tgdb_err "輸入格式不正確，請輸入有效序號、逗號、範圍，或輸入 A 代表全部。"
    done

    local -a targets=()
    local idx
    for idx in "${BACKUP_SELECTED_INSTANCES[@]}"; do
        targets+=("${archives[$((idx - 1))]}")
    done

    echo "將從遠端拉回以下備份："
    for archive in "${targets[@]}"; do
        if [ -f "$BACKUP_DIR/$archive" ]; then
            echo " - $archive（將覆蓋本機同名檔）"
        else
            echo " - $archive"
        fi
    done

    if ! ui_confirm_yn "確認拉回這些備份到本地嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消。"
        ui_pause
        return 0
    fi

    if _backup_rclone_restore_selected_to_local "${targets[@]}"; then
        ui_pause
        return 0
    fi

    ui_pause
    return 1
}

backup_archives_manage_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    while true; do
        clear
        echo "=================================="
        echo "❖ 已備份管理 ❖"
        echo "=================================="
        echo "備份位置：$BACKUP_DIR"
        echo "保留數量：全備份=$(_backup_full_max_count_get) / 指定備份=$(_backup_select_max_count_get)"
        echo "----------------------------------"
        _backup_print_managed_archives || true
        echo "----------------------------------"
        echo "1. 自訂限額備份數"
        echo "2. 刪除指定備份（可多選）"
        echo "3. 指定備份恢復"
        echo "4. 從 Rclone 遠端還原備份到本地"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="

        local choice
        read -r -e -p "請輸入選擇 [0-4]: " choice
        case "$choice" in
          1)
            backup_retention_config_interactive
            ui_pause
            ;;
          2)
            backup_delete_selected_archives_interactive
            ;;
          3)
            backup_restore_archive_interactive
            ;;
          4)
            backup_rclone_restore_to_local_interactive
            ;;
          0) return 0 ;;
          *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

# --- systemd --user 自動備份 ---

