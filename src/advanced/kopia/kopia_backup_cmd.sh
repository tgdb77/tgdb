#!/bin/bash

# Kopia 備份：CLI 命令與主入口
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_BACKUP_CMD_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_BACKUP_CMD_LOADED=1

_kopia_status_extra() {
  local status_file
  status_file="$(_kopia_backup_status_file)"
  if [ -f "$status_file" ]; then
    local last
    last="$(awk -F= '/^last_run_at=/{print $2; exit}' "$status_file" 2>/dev/null || true)"
    [ -n "${last:-}" ] && echo "上次執行：$last"
  fi
}

cmd_status() {
  tgdb_timer_print_status "$KOPIA_BACKUP_TIMER" "OnCalendar" "_kopia_status_extra"
}

cmd_repo_status() {
  load_system_config >/dev/null 2>&1 || true

  _kopia_ensure_container_running "kopia" || return 1
  _kopia_wait_exec_ready "kopia" || return 1

  local out rc=0
  out="$(_kopia_repository_status "kopia" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    tgdb_warn "目前尚未連接 Repository。請先執行 repo-setup-rclone。"
    echo "$out"
    return "$rc"
  fi
  echo "$out"
  return 0
}

cmd_repo_setup_rclone() {
  load_system_config >/dev/null 2>&1 || true

  local mode="${1:-auto}" remote_name="${2:-}" repo_dir="${3:-}"
  case "$mode" in
    auto|create|connect)
      ;;
    *)
      tgdb_fail "不支援的模式：$mode（僅支援 auto/create/connect）" 2 || return $?
      ;;
  esac

  if [ -z "${remote_name:-}" ]; then
    tgdb_fail "用法：$0 repo-setup-rclone <auto|create|connect> <remote_name> <repo_dir>" 2 || return $?
  fi
  if [ -z "${repo_dir:-}" ]; then
    tgdb_fail "請提供遠端備份目錄（repo_dir）。" 2 || return $?
  fi

  remote_name="${remote_name%:}"
  repo_dir="${repo_dir#/}"
  repo_dir="${repo_dir%/}"
  if [ -z "${remote_name:-}" ]; then
    tgdb_fail "remote_name 不可為空。" 2 || return $?
  fi
  if [ -z "${repo_dir:-}" ]; then
    tgdb_fail "repo_dir 不可為空。" 2 || return $?
  fi

  local remote_path
  remote_path="${remote_name}:${repo_dir}"

  _kopia_ensure_container_running "kopia" || return 1
  _kopia_wait_exec_ready "kopia" || return 1

  if ! _kopia_container_has_rclone "kopia"; then
    tgdb_fail "Kopia 容器內未找到 rclone，無法使用 rclone repository。" 1 || true
    return 1
  fi
  if ! _kopia_container_has_rclone_config "kopia"; then
    tgdb_fail "找不到 /app/rclone/rclone.conf，請先確認 $TGDB_DIR/rclone.conf 存在。" 1 || true
    return 1
  fi
  if ! _kopia_container_has_remote_name "kopia" "$remote_name"; then
    tgdb_fail "rclone 設定中找不到遠端：$remote_name" 1 || true
    return 1
  fi

  _kopia_exec "kopia" kopia repository disconnect >/dev/null 2>&1 || true

  local out rc=0
  case "$mode" in
    create)
      out="$(_kopia_repo_create_rclone "kopia" "$remote_path" 2>&1)" || rc=$?
      if [ "$rc" -ne 0 ]; then
        tgdb_fail "建立 Repository 失敗：$out" 1 || true
        return "$rc"
      fi
      ;;
    connect)
      out="$(_kopia_repo_connect_rclone "kopia" "$remote_path" 2>&1)" || rc=$?
      if [ "$rc" -ne 0 ]; then
        tgdb_fail "連接 Repository 失敗：$out" 1 || true
        return "$rc"
      fi
      ;;
    auto)
      out="$(_kopia_repo_connect_rclone "kopia" "$remote_path" 2>&1)" || rc=$?
      if [ "$rc" -ne 0 ]; then
        tgdb_warn "連接既有 Repository 失敗，改嘗試建立新 Repository：$remote_path"
        local out2 rc2=0
        out2="$(_kopia_repo_create_rclone "kopia" "$remote_path" 2>&1)" || rc2=$?
        if [ "$rc2" -ne 0 ]; then
          tgdb_fail "建立新 Repository 也失敗：$out2" 1 || true
          return "$rc2"
        fi
        out="$out2"
      fi
      ;;
  esac

  echo "$out"
  echo "✅ Repository 已連接：$remote_path"
  echo "ℹ️ 正在重載 Kopia Server 設定..."
  _kopia_reload_server "kopia" || {
    tgdb_warn "重載 Kopia Server 失敗，Web UI 可能不會立即顯示新設定。"
  }
  _kopia_repository_status "kopia" || true
  return 0
}

_kopia_backup_write_units() {
  local freq="$1"
  local runner_abs

  runner_abs="$(tgdb_timer_runner_script_path)"

  _write_user_unit "$KOPIA_BACKUP_SERVICE" "[Unit]\nDescription=TGDB Kopia Unified Backup (DB dump -> snapshot)\n\n[Service]\nType=oneshot\nEnvironment=TGDB_DBBACKUP_PG_DUMP_Z=${TGDB_DBBACKUP_PG_DUMP_Z:-0}\nExecStart=/bin/bash \"$runner_abs\" run kopia_backup timer\n"
  _write_user_unit "$KOPIA_BACKUP_TIMER" "[Unit]\nDescription=TGDB Kopia Unified Backup (DB dump -> snapshot)\n\n[Timer]\nOnCalendar=$freq\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"
}

_kopia_backup_ensure_units() {
  _kopia_backup_write_units "daily"
}

cmd_setup_timer() {
  local freq="${1:-daily}"
  tgdb_timer_validate_named_frequency "$freq" || return $?

  tgdb_timer_setup_managed "$KOPIA_BACKUP_TIMER" "_kopia_backup_write_units" "$freq" || return 1

  echo "✅ 已安裝並啟用：$KOPIA_BACKUP_TIMER（OnCalendar=$freq）"
  echo "提示：如需調整 PostgreSQL dump 壓縮，可設定 TGDB_DBBACKUP_PG_DUMP_Z（0-9；0=不壓縮）。"
  return 0
}

cmd_set_oncalendar() {
  local sched="$*"
  if [ -z "${sched:-}" ]; then
    tgdb_fail "用法：$0 set-oncalendar <OnCalendar>" 2 || return $?
  fi

  tgdb_timer_schedule_set "$KOPIA_BACKUP_TIMER" "OnCalendar" "$sched" || return 1
  echo "✅ 已更新 $KOPIA_BACKUP_TIMER 排程：$sched"
  return 0
}

cmd_enable_timer() {
  if tgdb_timer_enable_managed "$KOPIA_BACKUP_TIMER" "$KOPIA_BACKUP_SERVICE" "_kopia_backup_ensure_units"; then
    echo "✅ 已開啟：$KOPIA_BACKUP_TIMER"
    return 0
  fi

  tgdb_warn "無法直接開啟 $KOPIA_BACKUP_TIMER，已保留現有設定檔。"
  return 1
}

cmd_disable_timer() {
  if ! tgdb_timer_unit_exists "$KOPIA_BACKUP_TIMER" && ! tgdb_timer_unit_exists "$KOPIA_BACKUP_SERVICE"; then
    tgdb_warn "尚未建立 Kopia 定時備份任務，無需關閉。"
    return 0
  fi

  tgdb_timer_disable_units "$KOPIA_BACKUP_TIMER" "$KOPIA_BACKUP_SERVICE" || true
  echo "✅ 已關閉：$KOPIA_BACKUP_TIMER（保留設定檔）"
  return 0
}

cmd_remove_timer() {
  tgdb_timer_remove_units "$KOPIA_BACKUP_TIMER" "$KOPIA_BACKUP_SERVICE" || true
  echo "✅ 已移除：$KOPIA_BACKUP_TIMER / $KOPIA_BACKUP_SERVICE"
  return 0
}

cmd_restore_overwrite() {
  load_system_config >/dev/null 2>&1 || true
  _kopia_require_interactive || return $?

  if ! command -v diff >/dev/null 2>&1; then
    tgdb_fail "找不到 diff，無法執行 dry-run 差異摘要。" 1 || true
    return 1
  fi

  local backup_root tgdb_name
  backup_root="$(tgdb_backup_root)"
  tgdb_name="$(basename "$TGDB_DIR" 2>/dev/null || echo "app")"

  local main_source config_source quadlet_source source_mode quadlet_dir_name
  main_source="/data/$tgdb_name"
  config_source="/data/config"
  quadlet_dir_name="$(_kopia_quadlet_runtime_archive_dirname)"
  quadlet_source="/data/$quadlet_dir_name"
  source_mode="split"

  _kopia_ensure_container_running "kopia" || return 1
  _kopia_wait_exec_ready "kopia" || return 1
  if ! _kopia_repository_status "kopia" >/dev/null 2>&1; then
    tgdb_fail "尚未連接 Kopia Repository，請先執行「Kopia 遠端 Repository 設定」。" 1 || true
    return 1
  fi

  local all_raw="" all_rc=0
  all_raw="$(_kopia_snapshot_list_text "kopia" 2>&1)" || all_rc=$?
  if [ "$all_rc" -ne 0 ]; then
    tgdb_fail "取得快照清單失敗：$all_raw" 1 || true
    return "$all_rc"
  fi

  local -a main_rows=() main_candidates=() tried_sources=()
  local -A seen_main_sources=()
  local candidate
  main_candidates+=("/data/$tgdb_name")
  if [ "$tgdb_name" != "app" ]; then
    main_candidates+=("/data/app")
  fi
  main_candidates+=("/data")

  for candidate in "${main_candidates[@]}"; do
    if [ -n "${seen_main_sources["$candidate"]+x}" ]; then
      continue
    fi
    seen_main_sources["$candidate"]=1
    tried_sources+=("$candidate")

    mapfile -t main_rows < <(printf '%s\n' "$all_raw" | _kopia_snapshot_rows_for_source_from_all_text "$candidate")
    if [ ${#main_rows[@]} -gt 0 ]; then
      main_source="$candidate"
      break
    fi
  done

  if [ ${#main_rows[@]} -eq 0 ]; then
    local tried_desc=""
    tried_desc="$(IFS='、'; echo "${tried_sources[*]}")"
    tgdb_fail "找不到可用快照（已嘗試：$tried_desc），請先確認 Repository 與 snapshot source 路徑。" 1 || true
    return 1
  fi

  if [ "$main_source" = "/data" ]; then
    source_mode="root"
    tgdb_warn "偵測到來源快照為 /data，將使用 root 模式還原（自動拆回 $tgdb_name/config/$quadlet_dir_name）。"
  fi

  local -a main_ids=()
  local row
  for row in "${main_rows[@]}"; do
    main_ids+=("${row%%$'\t'*}")
  done

  local -a config_ids=() quadlet_ids=()
  if [ "$source_mode" = "split" ]; then
    if [ -d "$backup_root/config" ]; then
      mapfile -t config_ids < <(printf '%s\n' "$all_raw" | _kopia_snapshot_ids_for_source_from_all_text "$config_source" 2>/dev/null || true)
      if [ ${#config_ids[@]} -eq 0 ]; then
        tgdb_warn "未取得 $config_source 快照，後續將略過 config 還原。"
      fi
    fi
    if [ -d "$backup_root/$quadlet_dir_name" ]; then
      mapfile -t quadlet_ids < <(printf '%s\n' "$all_raw" | _kopia_snapshot_ids_for_source_from_all_text "$quadlet_source" 2>/dev/null || true)
      if [ ${#quadlet_ids[@]} -eq 0 ]; then
        tgdb_warn "未取得 $quadlet_source 快照，後續將略過 Quadlet runtime 還原。"
      fi
    elif [ -d "$backup_root/quadlet" ]; then
      quadlet_source="/data/quadlet"
      mapfile -t quadlet_ids < <(printf '%s\n' "$all_raw" | _kopia_snapshot_ids_for_source_from_all_text "$quadlet_source" 2>/dev/null || true)
      if [ ${#quadlet_ids[@]} -eq 0 ]; then
        tgdb_warn "未取得 $quadlet_source 快照，後續將略過 Quadlet runtime 還原。"
      fi
    fi
  fi

  local max_common
  max_common="${#main_ids[@]}"
  if [ "$source_mode" = "split" ]; then
    if [ ${#config_ids[@]} -gt 0 ] && [ "${#config_ids[@]}" -lt "$max_common" ]; then
      max_common="${#config_ids[@]}"
    fi
    if [ ${#quadlet_ids[@]} -gt 0 ] && [ "${#quadlet_ids[@]}" -lt "$max_common" ]; then
      max_common="${#quadlet_ids[@]}"
    fi
  fi
  if [ "$max_common" -lt 1 ]; then
    max_common=1
  fi

  # 預設選擇「最新且可對齊」的版本：
  # - 以時間戳（YYYY-MM-DD HH:MM:SS）挑最大值；
  # - 若無法解析時間，退回可對齊範圍末端。
  local latest_rank latest_ts
  latest_rank=1
  latest_ts=""
  local _rank _line _ts
  _rank=1
  for row in "${main_rows[@]}"; do
    _line="${row#*$'\t'}"
    _ts=""
    if [[ "$_line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([0-9]{2}:[0-9]{2}:[0-9]{2})[[:space:]] ]]; then
      _ts="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
      if [ -z "${latest_ts:-}" ] || [[ "$_ts" > "$latest_ts" ]]; then
        latest_ts="$_ts"
        latest_rank="$_rank"
      fi
    fi
    _rank=$((_rank + 1))
  done
  if [ -z "${latest_ts:-}" ]; then
    latest_rank="${#main_rows[@]}"
  fi
  if [ "$latest_rank" -gt "$max_common" ]; then
    latest_rank="$max_common"
  fi
  if [ "$latest_rank" -lt 1 ]; then
    latest_rank=1
  fi

  clear
  echo "=================================="
  echo "❖ Kopia 還原精靈（覆蓋模式）❖"
  echo "=================================="
  echo "步驟：快照選擇 -> 組成預覽 -> 還原到暫存(volume_dir/tmp) -> dry-run 差異 -> YES 覆蓋"
  echo "----------------------------------"
  echo "快照清單（來源：$main_source）"

  local idx=1 line tip
  for row in "${main_rows[@]}"; do
    line="${row#*$'\t'}"
    tip=""
    if [ "$idx" -eq "$latest_rank" ]; then
      tip=" (latest)"
    fi
    if [ "$idx" -gt "$max_common" ]; then
      tip="$tip [超出可對齊範圍]"
    fi
    printf '%2d. %s%s\n' "$idx" "$line" "$tip"
    idx=$((idx+1))
  done
  echo "----------------------------------"
  if [ "$source_mode" = "root" ]; then
    echo "可選版本範圍：1-$max_common（來源為 /data，將自動拆回 $tgdb_name/config/$quadlet_dir_name）"
  else
    echo "可對齊版本範圍：1-$max_common（確保主要目錄與 config/$quadlet_dir_name 版本一致）"
  fi

  local pick selected_rank selected_id
  selected_rank="$latest_rank"
  while true; do
    read -r -e -p "請輸入快照編號（直接 Enter 使用 latest，輸入 0 取消）: " pick
    if [ -z "${pick:-}" ]; then
      selected_rank="$latest_rank"
      break
    fi
    if [ "$pick" = "0" ]; then
      echo "操作已取消。"
      return 0
    fi

    if [[ "$pick" =~ ^[0-9]+$ ]]; then
      if [ "$pick" -ge 1 ] && [ "$pick" -le "$max_common" ]; then
        selected_rank="$pick"
        break
      fi
      tgdb_err "編號需介於 1-$max_common。"
      continue
    fi

    if [[ "$pick" =~ ^k[0-9a-f]{20,}$ ]]; then
      local found_rank
      found_rank=0
      local i
      for i in "${!main_ids[@]}"; do
        if [ "${main_ids[$i]}" = "$pick" ]; then
          found_rank=$((i+1))
          break
        fi
      done
      if [ "$found_rank" -ge 1 ] && [ "$found_rank" -le "$max_common" ]; then
        selected_rank="$found_rank"
        break
      fi
      tgdb_err "此 snapshot id 不在可對齊範圍（1-$max_common）。"
      continue
    fi

    tgdb_err "請輸入快照編號、snapshot id，或 0 取消。"
  done
  selected_id="${main_ids[$((selected_rank-1))]}"

  local -a restore_labels=() restore_sources=() restore_ids=() restore_subdirs=()
  if [ "$source_mode" = "root" ]; then
    restore_labels+=("data-root")
    restore_sources+=("$main_source")
    restore_ids+=("$selected_id")
    restore_subdirs+=(".")
  else
    restore_labels+=("$tgdb_name")
    restore_sources+=("$main_source")
    restore_ids+=("$selected_id")
    restore_subdirs+=("$tgdb_name")

    if [ ${#config_ids[@]} -ge "$selected_rank" ]; then
      restore_labels+=("config")
      restore_sources+=("$config_source")
      restore_ids+=("${config_ids[$((selected_rank-1))]}")
      restore_subdirs+=("config")
    fi
    if [ ${#quadlet_ids[@]} -ge "$selected_rank" ]; then
      restore_labels+=("${quadlet_source#/data/}")
      restore_sources+=("$quadlet_source")
      restore_ids+=("${quadlet_ids[$((selected_rank-1))]}")
      restore_subdirs+=("${quadlet_source#/data/}")
    fi
  fi

  echo "----------------------------------"
  echo "已選擇還原批次：#$selected_rank"
  local j
  for j in "${!restore_labels[@]}"; do
    echo "[$((j+1))] ${restore_labels[$j]} <- ${restore_sources[$j]} @ ${restore_ids[$j]}"
  done
  echo "----------------------------------"
  echo "組成預覽："
  for j in "${!restore_labels[@]}"; do
    _kopia_snapshot_preview "kopia" "${restore_ids[$j]}" "${restore_labels[$j]}" || true
    echo "----------------------------------"
  done

  if ! ui_confirm_yn "確認以上組成，繼續還原到暫存目錄嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    echo "操作已取消。"
    return 0
  fi

  local volume_dir stage_base stage_dir stage_rel stage_dir_container ts
  volume_dir="$(_kopia_volume_dir)"
  stage_base="$volume_dir/tmp"
  mkdir -p "$stage_base" 2>/dev/null || {
    tgdb_fail "無法建立暫存根目錄：$stage_base" 1 || true
    return 1
  }

  ts="$(date +%Y%m%d-%H%M%S)"
  stage_rel="tmp/restore-$ts"
  stage_dir="$volume_dir/$stage_rel"
  stage_dir_container="/repository/$stage_rel"
  mkdir -p "$stage_dir" 2>/dev/null || {
    tgdb_fail "無法建立暫存目錄：$stage_dir" 1 || true
    return 1
  }

  echo "⏳ 正在還原到暫存目錄：$stage_dir"
  if [ "$source_mode" = "root" ]; then
    local out rc=0
    out="$(_kopia_exec "kopia" kopia restore "$selected_id" "$stage_dir_container" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
      tgdb_fail "還原到暫存失敗（data-root）：$out" 1 || true
      echo "⚠️ 已保留暫存目錄供排查：$stage_dir"
      return "$rc"
    fi
  else
    for j in "${!restore_labels[@]}"; do
      local sid label subdir stage_target stage_target_container out rc=0
      sid="${restore_ids[$j]}"
      label="${restore_labels[$j]}"
      subdir="${restore_subdirs[$j]}"
      stage_target="$stage_dir/$subdir"
      stage_target_container="$stage_dir_container/$subdir"
      mkdir -p "$stage_target" 2>/dev/null || true

      out="$(_kopia_exec "kopia" kopia restore "$sid" "$stage_target_container" 2>&1)" || rc=$?
      if [ "$rc" -ne 0 ]; then
        tgdb_fail "還原到暫存失敗（$label）：$out" 1 || true
        echo "⚠️ 已保留暫存目錄供排查：$stage_dir"
        return "$rc"
      fi
    done
  fi

  local -a apply_labels=() apply_subdirs=()
  if [ "$source_mode" = "root" ]; then
    local root_sub
    for root_sub in "$tgdb_name" "config" "$quadlet_dir_name" "quadlet"; do
      if [ -d "$stage_dir/$root_sub" ]; then
        apply_labels+=("$root_sub")
        apply_subdirs+=("$root_sub")
      fi
    done
    if [ ${#apply_subdirs[@]} -eq 0 ]; then
      tgdb_fail "root 模式還原後未找到可套用目錄（$tgdb_name/config/$quadlet_dir_name）。" 1 || true
      echo "⚠️ 已保留暫存目錄供排查：$stage_dir"
      return 1
    fi
  else
    apply_labels=("${restore_labels[@]}")
    apply_subdirs=("${restore_subdirs[@]}")
  fi

  echo "----------------------------------"
  echo "dry-run 差異摘要："
  for j in "${!apply_labels[@]}"; do
    local label subdir src_dir dst_dir
    label="${apply_labels[$j]}"
    subdir="${apply_subdirs[$j]}"
    src_dir="$stage_dir/$subdir"
    dst_dir="$backup_root/$subdir"
    if ! _kopia_diff_dry_run_report "$src_dir" "$dst_dir" "$label"; then
      echo "⚠️ 已保留暫存目錄供排查：$stage_dir"
      return 1
    fi
    echo "----------------------------------"
  done

  echo "⚠️ 強制覆蓋提示："
  echo "此動作會直接覆蓋下列目標內容："
  for j in "${!apply_subdirs[@]}"; do
    echo " - $backup_root/${apply_subdirs[$j]}"
  done

  local confirm_yes
  read -r -e -p "請輸入 YES 確認正式覆蓋還原（其他輸入取消）: " confirm_yes
  if [ "${confirm_yes:-}" != "YES" ]; then
    echo "操作已取消。暫存目錄保留：$stage_dir"
    return 0
  fi

  _kopia_collect_active_user_units
  local had_running=0
  if [ ${#KOPIA_ACTIVE_CONTAINERS[@]} -gt 0 ] || [ ${#KOPIA_ACTIVE_PODS[@]} -gt 0 ]; then
    had_running=1
    echo "⏸️ 正在停止服務（覆蓋還原前置作業）..."
    local unit
    for unit in "${KOPIA_ACTIVE_CONTAINERS[@]}"; do
      _kopia_stop_unit_by_filename "$unit"
    done
    for unit in "${KOPIA_ACTIVE_PODS[@]}"; do
      _kopia_stop_unit_by_filename "$unit"
    done
  fi

  local apply_ok=1
  local quadlet_applied=0
  local config_applied=0
  for j in "${!apply_labels[@]}"; do
    local label subdir src_dir dst_dir
    label="${apply_labels[$j]}"
    subdir="${apply_subdirs[$j]}"
    src_dir="$stage_dir/$subdir"
    dst_dir="$backup_root/$subdir"
    echo "⏳ 正在覆蓋還原：[$label] $dst_dir"
    if ! _kopia_copy_replace_apply "$src_dir" "$dst_dir" "$label"; then
      apply_ok=0
      break
    fi
    if [ "$subdir" = "." ] || [ "$subdir" = "config" ]; then
      config_applied=1
    fi
    if [ "$subdir" = "$quadlet_dir_name" ] || [ "$subdir" = "quadlet" ]; then
      quadlet_applied=1
    fi
  done

  if [ "$apply_ok" -ne 1 ]; then
    if [ "$had_running" -eq 1 ]; then
      echo "▶️ 偵測到還原失敗，嘗試恢復原本服務..."
      _kopia_resume_active_units || true
    fi
    echo "⚠️ 還原未完成，已保留暫存目錄供排查：$stage_dir"
    return 1
  fi

  if [ "$quadlet_applied" -eq 1 ]; then
    echo "⏳ 正在同步 Quadlet runtime 至使用者單元目錄（~/.config/containers/systemd）..."
    _kopia_sync_quadlet_to_user_units || true
  fi

  if [ "$config_applied" -eq 1 ] && [ -d "$(rm_persist_timer_dir)" ]; then
    echo "⏳ 正在同步定時任務單元至使用者目錄（$(rm_user_systemd_dir)）..."
    if tgdb_timer_units_sync_persist_to_user; then
      if _kopia_has_systemctl_user; then
        echo "⏳ 正在重整並啟用所有定時任務單元..."
        tgdb_timer_units_enable_all_user || true
      else
        tgdb_warn "未偵測到 systemctl --user，無法自動啟用定時任務單元，請手動檢查。"
      fi
    else
      tgdb_warn "同步定時任務單元失敗，請手動檢查 $(rm_persist_timer_dir) 與 $(rm_user_systemd_dir)。"
    fi
  elif [ "$config_applied" -eq 1 ]; then
    echo "ℹ️ 本次還原未包含定時任務單元設定（config/timer），略過同步。"
  fi

  echo "⏳ 正在檢查/重建 DB data 目錄..."
  _kopia_prepare_db_data_dirs || true

  echo "⏳ 正在檢查/重建 Nginx cache 目錄..."
  _kopia_prepare_nginx_cache_dirs || true

  if _kopia_has_systemctl_user; then
    local runtime_apply_dir=""
    runtime_apply_dir="$(_kopia_find_runtime_quadlet_dir_in_tree "$backup_root" 2>/dev/null || true)"
    echo "⏳ 正在重整並啟用所有 Quadlet 單元..."
    if [ -n "${runtime_apply_dir:-}" ] && [ -d "$runtime_apply_dir" ]; then
      local -a restored_units=()
      local unit_name
      while IFS= read -r unit_name; do
        [ -n "$unit_name" ] && restored_units+=("$unit_name")
      done < <(_kopia_collect_unit_filenames_from_dir "$runtime_apply_dir")
      _kopia_enable_units_by_filenames "${restored_units[@]}" || true
    else
      _kopia_enable_all_units_from_units_dir || true
    fi
  elif [ "$had_running" -eq 1 ]; then
    echo "▶️ 未偵測到 systemctl --user，嘗試恢復原本服務..."
    _kopia_resume_active_units || true
  fi

  local db_restore_failed=0
  _kopia_restore_db_from_dumps || db_restore_failed=1
  if [ "$db_restore_failed" -ne 0 ]; then
    echo "⚠️ DB 恢復失敗，已保留暫存目錄供排查：$stage_dir"
    return 1
  fi

  if _kopia_remove_path_best_effort "$stage_dir"; then
    echo "✅ 已清除暫存目錄：$stage_dir"
  else
    tgdb_warn "還原成功但無法清除暫存目錄：$stage_dir（請手動清理）"
  fi

  echo "✅ 覆蓋還原完成。"
  echo "⚠️ 安全設定提醒：因安全因素，本流程不會自動套用 fail2ban / nftables 系統規則。"
  echo "   如有備份相關設定，請在確認後手動處理（Fail2ban 管理 / nftables 管理）。"
  return 0
}

kopia_backup_usage() {
  cat <<USAGE
用法: $0 <run|status|repo-status|repo-setup-rclone|generate-ignore|setup-timer|set-oncalendar|enable-timer|disable-timer|remove-timer|restore-overwrite>

  run                    執行一次（DB dump → snapshot）
  status                  顯示 timer 狀態
  repo-status             顯示目前 Repository 連線狀態
  repo-setup-rclone       設定 rclone repository
                         用法：repo-setup-rclone <auto|create|connect> <remote_name> <repo_dir>
  generate-ignore          產生/更新 .kopiaignore（自動排除 DB data 目錄）
  setup-timer <freq>       設定定期備份：daily|weekly|monthly
  set-oncalendar <expr>    更新 timer 的 OnCalendar（允許含空白）
  enable-timer             開啟既有 timer；若不存在則建立 daily
  disable-timer            關閉 timer，但保留設定檔
  remove-timer             移除定期備份 timer
  restore-overwrite        還原精靈（覆蓋模式：先還原到 volume_dir/tmp，再 dry-run 與 YES 覆蓋）

環境變數：
  TGDB_DBBACKUP_PG_DUMP_Z=0-9  PostgreSQL dump 壓縮等級（0=不壓縮，預設 0）
  KOPIA_OVERRIDE_SOURCE_USER    snapshot override-source 使用者（預設 root）
  KOPIA_OVERRIDE_SOURCE_HOST    snapshot override-source 主機名稱（預設 tgdb-kopia）
USAGE
}

kopia_backup_main() {
  local subcmd="${1:-}"
  case "$subcmd" in
    run) shift; cmd_run "$@" ;;
    status) shift; cmd_status "$@" ;;
    repo-status) shift; cmd_repo_status "$@" ;;
    repo-setup-rclone) shift; cmd_repo_setup_rclone "$@" ;;
    generate-ignore) shift; cmd_generate_ignore "$@" ;;
    setup-timer) shift; cmd_setup_timer "$@" ;;
    set-oncalendar) shift; cmd_set_oncalendar "$@" ;;
    enable-timer) shift; cmd_enable_timer "$@" ;;
    disable-timer) shift; cmd_disable_timer "$@" ;;
    remove-timer) shift; cmd_remove_timer "$@" ;;
    restore-overwrite) shift; cmd_restore_overwrite "$@" ;;
    *) kopia_backup_usage; return 1 ;;
  esac
}
