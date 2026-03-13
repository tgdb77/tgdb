#!/bin/bash

# 全系統備份管理模組
# shellcheck disable=SC2119 # ui_pause 使用預設訊息即可，無需轉傳參數
# 注意：此檔案可能會被 tgdb.sh source，也可能被 systemd timer 直接執行。
# 為避免污染呼叫端 shell options，僅在「直接執行」時啟用嚴格模式。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入共用工具
# shellcheck source=src/core/bootstrap.sh
source "$SCRIPT_DIR/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SCRIPT_DIR/core/quadlet_common.sh"

# 確保已載入系統設定（TGDB_DIR 等），避免在 systemd/獨立執行時變數未定義。
load_system_config

BACKUP_PREFIX="tgdb-backup"
BACKUP_MAX_COUNT=3
BACKUP_ROOT="${TGDB_BACKUP_ROOT:-$(dirname "$TGDB_DIR")}"
BACKUP_DIR="$BACKUP_ROOT/backup"

BACKUP_CONFIG_DIR="$(rm_persist_config_dir)"
CONTAINERS_SYSTEMD_DIR="$(rm_user_units_dir)"
BACKUP_CONTAINERS_SYSTEMD_DIR="$BACKUP_ROOT/quadlet"
BACKUP_TIMER_UNITS_DIR="$(rm_persist_timer_dir)"

USER_SD_DIR="$(rm_user_systemd_dir)"
BACKUP_SERVICE_NAME="tgdb-backup.service"
BACKUP_TIMER_NAME="tgdb-backup.timer"

# 避免在 set -u 模式下引用未初始化陣列
BACKUP_ACTIVE_CONTAINERS=()
BACKUP_ACTIVE_PODS=()

# 備份模組設定（放在持久化 config 內，會一起被備份/還原）
BACKUP_MODULE_DIR="$BACKUP_CONFIG_DIR/backup"
BACKUP_MODULE_CONFIG_FILE="$BACKUP_MODULE_DIR/config.conf"

# --- 共用工具函式 ---

_backup_has_systemctl_user() {
  command -v systemctl >/dev/null 2>&1
}

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

_backup_get_latest_backup() {
    local latest
    latest=$(_backup_list_backups_newest_first | head -n1 || true)
    if [ -z "$latest" ]; then
        return 1
    fi
    LATEST_BACKUP="$latest"
    return 0
}

_backup_cleanup_old() {
    local files=()
    mapfile -t files < <(_backup_list_backups_newest_first)
    local count=${#files[@]}
    if [ "$count" -le "$BACKUP_MAX_COUNT" ]; then
        return 0
    fi

    local i
    for ((i = BACKUP_MAX_COUNT; i < count; i++)); do
        local f="${files[$i]}"
        [ -f "$f" ] || continue
        echo "🗑️ 移除舊備份：$f"
        rm -f -- "$f" || true
    done
}

# --- 備份與還原 ---

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
        if cp -a "$CONTAINERS_SYSTEMD_DIR/." "$BACKUP_CONTAINERS_SYSTEMD_DIR/"; then
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
        if ! cp -a "$BACKUP_CONTAINERS_SYSTEMD_DIR/." "$CONTAINERS_SYSTEMD_DIR/"; then
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

# --- systemd --user 自動備份 ---

_backup_systemd_ready() {
    if ! command -v systemctl >/dev/null 2>&1; then
        tgdb_warn "未偵測到 systemd，無法使用自動備份。"
        return 1
    fi
    mkdir -p "$USER_SD_DIR"
    return 0
}

backup_timer_ensure_units() {
    local runner_abs svc_content tim_content

    runner_abs="$(tgdb_timer_runner_script_path)"
    svc_content="[Unit]\nDescription=TGDB 全系統備份\n\n[Service]\nType=oneshot\nExecStart=/bin/bash \"$runner_abs\" run backup timer\n"
    tim_content="[Unit]\nDescription=TGDB 自動備份\n\n[Timer]\nOnCalendar=daily\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"

    tgdb_timer_write_user_unit "$BACKUP_SERVICE_NAME" "$svc_content"
    tgdb_timer_write_user_unit "$BACKUP_TIMER_NAME" "$tim_content"
}

backup_enable_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    if tgdb_timer_enable_managed "$BACKUP_TIMER_NAME" "$BACKUP_SERVICE_NAME" "backup_timer_ensure_units"; then
        echo "✅ 已開啟自動備份任務。"
        return 0
    fi

    tgdb_warn "無法直接開啟 $BACKUP_TIMER_NAME，已保留現有設定檔。"
    return 1
}

backup_disable_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    if ! tgdb_timer_unit_exists "$BACKUP_TIMER_NAME" && ! tgdb_timer_unit_exists "$BACKUP_SERVICE_NAME"; then
        tgdb_warn "尚未建立自動備份任務，無需關閉。"
        return 0
    fi

    tgdb_timer_disable_units "$BACKUP_TIMER_NAME" "$BACKUP_SERVICE_NAME" || true
    echo "✅ 已關閉自動備份任務（保留設定檔）。"
}

backup_remove_timer() {
    if ! _backup_systemd_ready; then
        return 1
    fi

    tgdb_timer_remove_units "$BACKUP_TIMER_NAME" "$BACKUP_SERVICE_NAME" || true
    echo "✅ 已停用並移除自動備份 timer/service。"
}

backup_timer_run_once() {
    if [ -f "$SCRIPT_DIR/fail2ban_manager.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/fail2ban_manager.sh"
        backup_fail2ban_local
    fi
    if [ -f "$SCRIPT_DIR/nftables.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/nftables.sh"
        nftables_backup
    fi
    backup_create
}

backup_rclone_sync_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    _backup_ensure_dirs || return 1

    local cur
    cur="$(_backup_rclone_remote_get 2>/dev/null || true)"

    # 簡單切換模式：
    # - 未開啟：走「新增/開啟」流程
    # - 已開啟：走「關閉」流程
    if [ -n "${cur:-}" ]; then
        echo "目前狀態：已開啟（目的：${cur%:}:tgdb-backup）"
        if ui_confirm_yn "確認關閉 Rclone 遠端同步？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            _backup_rclone_remote_disable
            echo "✅ 已關閉 Rclone 遠端同步。"
        else
            echo "操作已取消。"
        fi
        ui_pause
        return 0
    fi

    if ! command -v rclone >/dev/null 2>&1; then
        tgdb_warn "未偵測到 rclone，請先至「Rclone 掛載」功能安裝/設定後再使用。"
        ui_pause
        return 1
    fi

    echo "目前狀態：未開啟"
    echo "將在每次「建立備份」完成後，自動同步到遠端根目錄的 tgdb-backup。"
    echo ""
    echo "目前可用遠端（rclone listremotes）："
    rclone listremotes 2>/dev/null || true
    echo ""
    local remote
    read -r -e -p "輸入遠端名稱（例如 gdrive 或 gdrive:；輸入 0 取消）: " remote
    if [ "${remote:-}" = "0" ] || [ -z "${remote:-}" ]; then
        echo "操作已取消。"
        ui_pause
        return 0
    fi
    if [[ ! "$remote" =~ ^[A-Za-z0-9._-]+:?$ ]]; then
        tgdb_err "遠端名稱格式不合法：$remote"
        ui_pause
        return 1
    fi
    _backup_rclone_remote_set "$remote"
    echo "✅ 已開啟 Rclone 遠端同步：${remote%:}:tgdb-backup"

    if ui_confirm_yn "是否立即同步目前備份到遠端？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        _backup_rclone_sync_to_remote || true
    fi
    ui_pause
    return 0
}

backup_timer_get_schedule() {
    tgdb_timer_schedule_get "$BACKUP_TIMER_NAME" "OnCalendar"
}

backup_timer_set_schedule() {
    local sched="$*"

    [ -n "${sched:-}" ] || {
        tgdb_fail "排程不可為空。" 2 || return $?
    }

    tgdb_timer_schedule_set "$BACKUP_TIMER_NAME" "OnCalendar" "$sched" || return 1
    echo "✅ 已更新 $BACKUP_TIMER_NAME 排程：$sched"
}

backup_timer_status_extra() {
    local remote

    remote="$(_backup_rclone_remote_get 2>/dev/null || true)"
    if [ -n "${remote:-}" ]; then
        echo "Rclone 遠端同步：已啟用（目的：${remote%:}:tgdb-backup）"
    else
        echo "Rclone 遠端同步：未啟用"
    fi
    echo "備份位置：$BACKUP_DIR"
}

backup_timer_special_menu() {
    backup_rclone_sync_menu
}

tgdb_timer_define_backup_task() {
    # shellcheck disable=SC2034 # 供共用選單/回呼跨檔案讀取
    {
        TGDB_TIMER_TASK_ID="backup"
        TGDB_TIMER_TASK_TITLE="自動備份"
        TGDB_TIMER_TIMER_UNIT="$BACKUP_TIMER_NAME"
        TGDB_TIMER_SERVICE_UNIT="$BACKUP_SERVICE_NAME"
        TGDB_TIMER_SCHEDULE_MODE="oncalendar"
        TGDB_TIMER_SCHEDULE_KEY="OnCalendar"
        TGDB_TIMER_SCHEDULE_HINT="OnCalendar 支援 daily/weekly/monthly，或 *-*-* 03:00:00 這類完整表達式。"
        TGDB_TIMER_SPECIAL_LABEL="切換 Rclone 遠端同步（特殊功能）"
        TGDB_TIMER_ENABLE_CB="backup_enable_timer"
        TGDB_TIMER_DISABLE_CB="backup_disable_timer"
        TGDB_TIMER_REMOVE_CB="backup_remove_timer"
        TGDB_TIMER_GET_SCHEDULE_CB="backup_timer_get_schedule"
        TGDB_TIMER_SET_SCHEDULE_CB="backup_timer_set_schedule"
        TGDB_TIMER_RUN_NOW_CB="backup_timer_run_once"
        TGDB_TIMER_STATUS_EXTRA_CB="backup_timer_status_extra"
        TGDB_TIMER_SPECIAL_CB="backup_timer_special_menu"
        TGDB_TIMER_HEALTHCHECKS_SUPPORTED="1"
        TGDB_TIMER_RUN_VIA_RUNNER="1"
        TGDB_TIMER_CONTEXT_KIND="built_in"
        TGDB_TIMER_CONTEXT_ID="backup"
    }
}

backup_timer_menu() {
    tgdb_timer_task_menu "backup"
}

# --- 互動主選單（由 tgdb.sh 呼叫） ---

backup_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 全系統備份管理 ❖"
        echo "=================================="
        echo "TGDB 目錄: $TGDB_DIR"
        echo "備份位置: $BACKUP_DIR (最多三個)"
        echo "策略提示：備份會自動停機（冷備份）確保一致性；還原後會自動重整並啟用所有 Quadlet 單元。"
        echo "新環境使用者名稱需一致，避免目錄錯誤"
        echo "----------------------------------"
        echo "1. 立即建立備份"
        echo "2. 還原最新備份"
        echo "3. 自動備份設定（systemd .timer）"
        echo "4. Kopia 管理（熱備：DB dump → snapshot）"
        echo "----------------------------------"
        echo "0. 返回主選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-4]: " choice
        case "$choice" in
            1)
                # 先嘗試備份 Fail2ban 與 nftables 設定，供日後手動還原使用
                if [ -f "$SCRIPT_DIR/fail2ban_manager.sh" ]; then
                    # shellcheck source=/dev/null
                    source "$SCRIPT_DIR/fail2ban_manager.sh"
                    backup_fail2ban_local
                fi
                if [ -f "$SCRIPT_DIR/nftables.sh" ]; then
                    # shellcheck source=/dev/null
                    source "$SCRIPT_DIR/nftables.sh"
                    nftables_backup
                fi
                backup_create
                ui_pause
                ;;
            2) backup_restore_latest_interactive ;;
            3) backup_timer_menu ;;
            4)
                if [ -f "$SCRIPT_DIR/advanced/kopia-p.sh" ]; then
                    # shellcheck source=/dev/null
                    source "$SCRIPT_DIR/advanced/kopia-p.sh"
                    kopia_p_menu || true
                else
                    tgdb_fail "找不到 Kopia 模組：$SCRIPT_DIR/advanced/kopia-p.sh" 1 || true
                    ui_pause
                fi
                ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

# --- CLI 入口：提供給 systemd .service 使用 ---

backup_cli_main() {
    local subcmd="${1:-}"
    case "$subcmd" in
        auto-backup)
            backup_create
            ;;
        *)
            tgdb_fail "用法: $0 [auto-backup]" 1 || return $?
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    backup_cli_main "$@" || exit $?
fi
