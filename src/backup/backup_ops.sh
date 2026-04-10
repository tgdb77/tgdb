#!/bin/bash

# 全系統備份：建立與還原流程
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_BACKUP_OPS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_OPS_LOADED=1

backup_create() {
    _backup_ensure_dirs || return 1
    tgdb_timer_units_stage_to_persist || true

    local ts archive
    ts=$(date +%Y%m%d-%H%M%S)
    archive="$BACKUP_DIR/${BACKUP_PREFIX}-${ts}.tar.gz"

    local tgdb_name
    tgdb_name="$(basename "$TGDB_DIR")"

    echo "=================================="
    echo "❖ 建立全系統備份 ❖"
    echo "=================================="
    echo "策略：將先自動停機再備份（冷備份），避免 Postgres/SQLite 不一致；備份完成後自動恢復。"
    echo "備份根目錄: $BACKUP_ROOT"
    echo "備份檔案目錄: $BACKUP_DIR"
    local remote
    remote="$(_backup_rclone_remote_get 2>/dev/null || true)"
    if [ -n "${remote:-}" ]; then
        echo "Rclone 同步: 已啟用（目的：${remote%:}:tgdb-backup）"
    else
        echo "Rclone 同步: 未啟用"
    fi
    echo "包含內容:"
    echo " - $tgdb_name（TGDB_DIR）"
    if [ -d "$TGDB_DIR/nftables" ]; then
        echo "   ↳ $TGDB_DIR/nftables（Nftables 規則備份）"
    fi
    if [ -d "$TGDB_DIR/fail2ban" ]; then
        echo "   ↳ $TGDB_DIR/fail2ban（Fail2ban .local 備份）"
    fi
    if [ -d "$BACKUP_CONFIG_DIR" ]; then
        echo " - config（持久化設定/紀錄：$BACKUP_CONFIG_DIR）"
        if [ -d "$BACKUP_TIMER_UNITS_DIR" ]; then
            echo "   ↳ $BACKUP_TIMER_UNITS_DIR（定時任務單元備份）"
        fi
    fi
    if [ -d "$CONTAINERS_SYSTEMD_DIR" ]; then
        echo " - $CONTAINERS_SYSTEMD_DIR（Quadlet 單元設定）"
    else
        echo " - （略過）未找到 $CONTAINERS_SYSTEMD_DIR"
    fi

    # nginx cache 目錄通常為暫存用途，且可能因容器內使用者/權限造成不可讀（tar: Permission denied）。
    # 這些暫存可由 nginx 重新建立，因此預設略過以避免整體備份失敗。
    local -a tar_excludes=()
    if [ -d "$TGDB_DIR/nginx/cache" ]; then
        echo " - （略過）$tgdb_name/nginx/cache（Nginx 暫存快取，避免權限問題）"
        tar_excludes+=(--exclude="$tgdb_name/nginx/cache")
    fi

    echo "備份檔案: $archive"
    echo "----------------------------------"

    _backup_stop_for_cold_snapshot

    local items=()
    items+=("$tgdb_name")
    if [ -d "$BACKUP_CONFIG_DIR" ]; then
        items+=("config")
    fi
    if [ -d "$CONTAINERS_SYSTEMD_DIR" ]; then
        rm -rf -- "$BACKUP_CONTAINERS_SYSTEMD_DIR"
        mkdir -p "$BACKUP_CONTAINERS_SYSTEMD_DIR"
        if podman unshare cp -a "$CONTAINERS_SYSTEMD_DIR/." "$BACKUP_CONTAINERS_SYSTEMD_DIR/"; then
            items+=("quadlet")
        else
            tgdb_warn "無法備份 $CONTAINERS_SYSTEMD_DIR，略過此目錄。"
        fi
    fi

    if tar -czf "$archive" -C "$BACKUP_ROOT" "${tar_excludes[@]}" "${items[@]}"; then
        _backup_resume_after_cold_snapshot
        echo "✅ 備份完成：$archive"
        _backup_cleanup_old
        _backup_rclone_sync_to_remote || true
        return 0
    fi

    local rc=$?
    _backup_resume_after_cold_snapshot
    tgdb_fail "建立備份失敗：$archive" "$rc" || return $?
}

backup_create_selected() {
    _backup_ensure_dirs || return 1

    if [ "$#" -le 0 ]; then
        tgdb_fail "未提供任何要備份的實例。" 1 || return $?
    fi

    local ts archive stage_dir tgdb_name
    ts=$(date +%Y%m%d-%H%M%S)
    archive="$BACKUP_DIR/${BACKUP_SELECT_PREFIX}-${ts}.tar.gz"
    stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/tgdb_select_backup.XXXXXX")"
    tgdb_name="$(basename "$TGDB_DIR")"

    _backup_stop_selected_for_cold_snapshot "$@"

    local ok_count=0
    local name
    for name in "$@"; do
        if _backup_stage_selected_instance "$stage_dir" "$tgdb_name" "$name"; then
            ok_count=$((ok_count + 1))
        fi
    done

    if [ "$ok_count" -le 0 ]; then
        rm -rf "$stage_dir" 2>/dev/null || true
        _backup_resume_after_cold_snapshot
        tgdb_fail "沒有任何可備份的指定實例，已取消。" 1 || return $?
    fi

    echo "=================================="
    echo "❖ 建立指定實例備份 ❖"
    echo "=================================="
    echo "策略：沿用冷備份，僅停止所選實例相關服務。"
    echo "備份位置: $archive"
    echo "實例數量: $ok_count"
    echo "包含內容:"
    for name in "$@"; do
        echo " - $name"
    done
    echo "----------------------------------"

    local -a items=()
    [ -d "$stage_dir/$tgdb_name" ] && items+=("$tgdb_name")
    [ -d "$stage_dir/config" ] && items+=("config")
    [ -d "$stage_dir/quadlet" ] && items+=("quadlet")

    if [ ${#items[@]} -eq 0 ]; then
        rm -rf "$stage_dir" 2>/dev/null || true
        _backup_resume_after_cold_snapshot
        tgdb_fail "指定備份暫存內容為空，已取消。" 1 || return $?
    fi

    if podman unshare tar -czf "$archive" -C "$stage_dir" "${items[@]}"; then
        rm -rf "$stage_dir" 2>/dev/null || true
        _backup_resume_after_cold_snapshot
        echo "✅ 指定實例備份完成：$archive"
        _backup_cleanup_old_by_prefix "$BACKUP_SELECT_PREFIX" "$(_backup_select_max_count_get)"
        return 0
    fi

    local rc=$?
    rm -rf "$stage_dir" 2>/dev/null || true
    _backup_resume_after_cold_snapshot
    tgdb_fail "建立指定備份失敗：$archive" "$rc" || return $?
}

backup_create_selected_interactive() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    if ! _backup_pick_instances_interactive; then
        echo "操作已取消。"
        ui_pause
        return 0
    fi

    if ! ui_confirm_yn "確認要備份以上指定實例嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消。"
        ui_pause
        return 0
    fi

    backup_create_selected "${BACKUP_SELECTED_INSTANCES[@]}"
    ui_pause
}

backup_select_targets_configure_interactive() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    if ! _backup_pick_instances_interactive; then
        echo "操作已取消。"
        return 1
    fi

    local joined=""
    local name
    for name in "${BACKUP_SELECTED_INSTANCES[@]}"; do
        joined+="${joined:+ }$name"
    done
    _backup_select_targets_set "$joined"
    echo "✅ 已設定指定備份實例：$joined"
    return 0
}

_backup_restore_from_archive() {
    local archive="$1"

    if [ -z "$archive" ] || [ ! -f "$archive" ]; then
        tgdb_fail "找不到備份檔：$archive" 1 || return $?
    fi

    echo "⏸️ 正在停止服務（還原前置作業）..."
    _backup_collect_active_user_units
    local had_running=0
    if [ ${#BACKUP_ACTIVE_CONTAINERS[@]} -gt 0 ] || [ ${#BACKUP_ACTIVE_PODS[@]} -gt 0 ]; then
        had_running=1
        local u
        for u in "${BACKUP_ACTIVE_CONTAINERS[@]}"; do
            _backup_stop_unit_by_filename "$u"
        done
        for u in "${BACKUP_ACTIVE_PODS[@]}"; do
            _backup_stop_unit_by_filename "$u"
        done
    fi

    mkdir -p "$BACKUP_ROOT"

    if ! tar -xzf "$archive" -C "$BACKUP_ROOT"; then
        if [ "$had_running" -eq 1 ]; then
            _backup_resume_after_cold_snapshot
        fi
        tgdb_fail "解壓縮備份失敗：$archive" 1 || return $?
    fi

    if [ -d "$BACKUP_CONFIG_DIR" ]; then
        echo "✅ 已還原持久化設定目錄：$BACKUP_CONFIG_DIR"
    else
        tgdb_warn "還原後未找到 $BACKUP_CONFIG_DIR（config），可能備份中未包含，已略過。"
    fi

    if [ -d "$BACKUP_TIMER_UNITS_DIR" ]; then
        echo "同步定時任務單元設定：$BACKUP_TIMER_UNITS_DIR -> $USER_SD_DIR"
        if ! tgdb_timer_units_sync_persist_to_user; then
            tgdb_warn "無法還原定時任務單元至 $USER_SD_DIR，請手動檢查。"
        else
            if _backup_has_systemctl_user; then
                echo "⏳ 正在重整並啟用所有定時任務單元..."
                tgdb_timer_units_enable_all_user || true
            else
                tgdb_warn "未偵測到 systemctl --user，無法自動啟用定時任務單元，請手動檢查。"
            fi
        fi
    else
        echo "ℹ️ 備份中未包含定時任務單元設定（config/timer），略過還原。"
    fi

    local restored_quadlet_ok=0
    if [ -d "$BACKUP_CONTAINERS_SYSTEMD_DIR" ]; then
        echo "同步 Quadlet 單元設定：$BACKUP_CONTAINERS_SYSTEMD_DIR -> $CONTAINERS_SYSTEMD_DIR"
        mkdir -p "$CONTAINERS_SYSTEMD_DIR"
        _backup_clear_user_quadlet_units || true
        if ! podman unshare cp -a "$BACKUP_CONTAINERS_SYSTEMD_DIR/." "$CONTAINERS_SYSTEMD_DIR/"; then
            tgdb_warn "無法還原 Quadlet 單元設定至 $CONTAINERS_SYSTEMD_DIR，請手動檢查。"
        else
            if _backup_has_systemctl_user; then
                echo "⏳ 正在重整並啟用所有單元..."
                _backup_enable_all_units_from_units_dir
                restored_quadlet_ok=1
            else
                tgdb_warn "未偵測到 systemctl --user，無法自動啟用單元，請手動啟動相關服務。"
            fi
        fi
    else
        echo "ℹ️ 備份中未包含 Quadlet 單元設定（quadlet），略過還原。"
    fi

    if [ "$restored_quadlet_ok" -eq 0 ] && [ "$had_running" -eq 1 ]; then
        _backup_resume_after_cold_snapshot
    fi

    echo "⚠️ 安全設定提醒：因安全因素，本流程不會自動套用 fail2ban / nftables 系統規則。"
    echo "   如有備份相關設定，請在確認後手動處理（Fail2ban 管理 / nftables 管理）。"

    return 0
}

_backup_restore_selected_instance_from_archive() {
    local archive="$1"
    local name="$2"

    if [ -z "$archive" ] || [ ! -f "$archive" ]; then
        tgdb_fail "找不到指定備份檔：$archive" 1 || return $?
    fi
    if [ -z "${name:-}" ]; then
        tgdb_fail "未指定要還原的實例名稱。" 1 || return $?
    fi

    local extract_dir tgdb_name src_instance_dir dest_instance_dir
    extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/tgdb_select_restore.XXXXXX")"
    tgdb_name="$(basename "$TGDB_DIR")"

    if ! tar -xzf "$archive" -C "$extract_dir"; then
        rm -rf "$extract_dir" 2>/dev/null || true
        tgdb_fail "解壓縮指定備份失敗：$archive" 1 || return $?
    fi

    src_instance_dir="$extract_dir/$tgdb_name/$name"
    dest_instance_dir="$TGDB_DIR/$name"
    if [ ! -d "$src_instance_dir" ]; then
        rm -rf "$extract_dir" 2>/dev/null || true
        tgdb_fail "備份檔中找不到指定實例：$name" 1 || return $?
    fi

    _backup_collect_active_units_for_instances "$name"
    local had_running=0
    if [ ${#BACKUP_ACTIVE_CONTAINERS[@]} -gt 0 ] || [ ${#BACKUP_ACTIVE_PODS[@]} -gt 0 ]; then
        had_running=1
        local u
        echo "⏸️ 正在停止指定實例相關服務（還原前置作業）..."
        for u in "${BACKUP_ACTIVE_CONTAINERS[@]}"; do
            _backup_stop_unit_by_filename "$u"
        done
        for u in "${BACKUP_ACTIVE_PODS[@]}"; do
            _backup_stop_unit_by_filename "$u"
        done
    fi

    local staging_replace="${TGDB_DIR}/.${name}.tgdb-restore.$$"
    rm -rf "$staging_replace" 2>/dev/null || true
    if ! podman unshare cp -a "$src_instance_dir" "$staging_replace"; then
        rm -rf "$extract_dir" "$staging_replace" 2>/dev/null || true
        if [ "$had_running" -eq 1 ]; then
            _backup_resume_after_cold_snapshot
        fi
        tgdb_fail "無法準備實例資料還原內容：$name" 1 || return $?
    fi

    if [ -e "$dest_instance_dir" ]; then
        rm -rf "$dest_instance_dir" 2>/dev/null || true
    fi
    if ! mv "$staging_replace" "$dest_instance_dir"; then
        rm -rf "$extract_dir" "$staging_replace" 2>/dev/null || true
        if [ "$had_running" -eq 1 ]; then
            _backup_resume_after_cold_snapshot
        fi
        tgdb_fail "無法寫入還原後的實例資料夾：$dest_instance_dir" 1 || return $?
    fi

    if [ -d "$extract_dir/config" ]; then
        mkdir -p "$BACKUP_ROOT/config"
        if ! podman unshare cp -a "$extract_dir/config/." "$BACKUP_ROOT/config/"; then
            tgdb_warn "還原 config 片段失敗，請手動檢查：$archive"
        else
            echo "✅ 已還原設定紀錄：config"
        fi
    fi

    local -a restored_units=()
    if [ -d "$extract_dir/quadlet" ]; then
        mkdir -p "$CONTAINERS_SYSTEMD_DIR"
        local f
        while IFS= read -r -d $'\0' f; do
            podman unshare cp -a "$f" "$CONTAINERS_SYSTEMD_DIR/" || {
                tgdb_warn "還原 Quadlet 單元失敗：$(basename "$f")"
                continue
            }
            restored_units+=("$(basename "$f")")
        done < <(find "$extract_dir/quadlet" -maxdepth 1 -type f -print0 2>/dev/null)
    fi

    rm -rf "$extract_dir" 2>/dev/null || true

    _backup_ensure_restored_instance_volume_dir "$name" || true

    if [ ${#restored_units[@]} -gt 0 ]; then
        echo "⏳ 正在重整並啟用已還原的 Quadlet 單元..."
        _backup_enable_units_by_filenames "${restored_units[@]}" || true
    elif [ "$had_running" -eq 1 ]; then
        _backup_resume_after_cold_snapshot
    fi

    echo "⚠️ 注意：指定還原僅覆蓋同名實例的設定層 / instance 結構 / Quadlet，不包含 volume_dir。"
    return 0
}

backup_restore_selected_latest_multi_interactive() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    local -a names=()
    local n
    while IFS= read -r n; do
        [ -n "$n" ] && names+=("$n")
    done < <(_backup_list_select_backup_instance_names)

    if [ ${#names[@]} -eq 0 ]; then
        tgdb_err "尚未找到任何指定實例備份。"
        ui_pause
        return 1
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 還原指定實例最新備份 ❖"
        echo "=================================="
        echo "可還原的實例："
        local i
        for ((i = 0; i < ${#names[@]}; i++)); do
            printf '%2d. %s\n' "$((i + 1))" "${names[$i]}"
        done
        echo "----------------------------------"
        echo "提示：可多選，支援空白 / 逗號 / 範圍，例如：1 3 5-7"
        echo "0. 取消"
        echo "=================================="

        local pick_raw
        read -r -e -p "請輸入要還原的實例序號（輸入 0 取消）: " pick_raw
        pick_raw="${pick_raw//[$'\t\r\n']/ }"
        pick_raw="${pick_raw#"${pick_raw%%[![:space:]]*}"}"
        pick_raw="${pick_raw%"${pick_raw##*[![:space:]]}"}"

        if [ "$pick_raw" = "0" ] || [ -z "$pick_raw" ]; then
            echo "操作已取消。"
            ui_pause
            return 0
        fi

        if ! _backup_parse_multi_name_selection "$pick_raw" "${names[@]}"; then
            tgdb_err "輸入格式不正確，請輸入有效序號、逗號或範圍。"
            sleep 1
            continue
        fi

        echo "將還原以下實例的最新指定備份："
        for n in "${BACKUP_SELECTED_INSTANCES[@]}"; do
            echo " - $n"
            if [ -d "$TGDB_DIR/$n" ]; then
                echo "   ⚠️ 偵測到現有同名實例，還原時將直接覆蓋。"
            fi
        done

        if ! ui_confirm_yn "確認繼續嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            echo "操作已取消。"
            ui_pause
            return 0
        fi

        local ok=0 fail=0 archive
        for n in "${BACKUP_SELECTED_INSTANCES[@]}"; do
            archive=""
            if ! _backup_get_latest_select_backup_for_instance "$n"; then
                tgdb_warn "找不到 $n 的指定備份，已略過。"
                fail=$((fail + 1))
                continue
            fi
            archive="$LATEST_BACKUP"

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
    done
}

backup_restore_latest_interactive() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    if ! _backup_get_latest_backup; then
        tgdb_err "尚未找到任何備份檔（$BACKUP_DIR/${BACKUP_PREFIX}-*.tar.gz）。"
        ui_pause
        return 1
    fi

    echo "=================================="
    echo "❖ 還原最新備份 ❖"
    echo "=================================="
    echo "目標根目錄: $BACKUP_ROOT"
    echo "將還原自: $LATEST_BACKUP"
    echo "----------------------------------"
    echo "此動作會覆蓋 $TGDB_DIR 與 $BACKUP_CONFIG_DIR 的內容，"
    echo "並根據備份還原 $CONTAINERS_SYSTEMD_DIR（Podman Quadlet 單元）與 $USER_SD_DIR（定時任務單元）。"
    echo "建議在還原前先停止相關服務（Podman/Nginx 等）。"
    if ! ui_confirm_yn "確認繼續嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        echo "操作已取消。"
        ui_pause
        return 0
    fi

    if _backup_restore_from_archive "$LATEST_BACKUP"; then
        echo "✅ 已從最新備份還原：$LATEST_BACKUP"
    else
        tgdb_err "還原失敗：$LATEST_BACKUP"
        ui_pause
        return 1
    fi
    ui_pause
}

backup_restore_latest_cli() {
    _backup_ensure_dirs || return 1

    if ! _backup_get_latest_backup; then
        tgdb_err "尚未找到任何備份檔（$BACKUP_DIR/${BACKUP_PREFIX}-*.tar.gz）。"
        return 1
    fi

    echo "=================================="
    echo "❖ 還原最新備份（CLI）❖"
    echo "=================================="
    echo "目標根目錄: $BACKUP_ROOT"
    echo "將還原自: $LATEST_BACKUP"
    echo "----------------------------------"
    echo "此動作會覆蓋 $TGDB_DIR 與 $BACKUP_CONFIG_DIR 的內容，並還原 $CONTAINERS_SYSTEMD_DIR（Podman Quadlet 單元）與 $USER_SD_DIR（定時任務單元），且不會再互動確認。"

    if _backup_restore_from_archive "$LATEST_BACKUP"; then
        echo "✅ 已從最新備份還原（CLI）：$LATEST_BACKUP"
        return 0
    fi
    tgdb_fail "還原失敗（CLI）：$LATEST_BACKUP" 1 || return $?
}

backup_restore_selected_latest_interactive() {
    backup_restore_selected_latest_multi_interactive
}

