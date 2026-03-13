#!/bin/bash

# Game Server：管理流程（單元控制 / 日誌 / LinuxGSM / 移除）
# 注意：此檔案為 library，會被 source；請勿在此更改 shell options。

_gameserver_is_safe_delete_path() {
  local target="$1"
  [ -n "$target" ] || return 1

  local resolved
  resolved="$(readlink -f -- "$target" 2>/dev/null || printf '%s' "$target")"

  case "$resolved" in
    "/"|"/home"|"/root"|"/var"|"/usr"|"/etc"|"/opt"|"/srv"|"/bin"|"/sbin"|"/lib"|"/lib64"|"/boot"|"/dev"|"/proc"|"/sys"|"/run")
      return 1
      ;;
  esac

  if [ -n "${HOME:-}" ]; then
    local home_resolved
    home_resolved="$(readlink -f -- "$HOME" 2>/dev/null || printf '%s' "$HOME")"
    if [ "$resolved" = "$home_resolved" ]; then
      return 1
    fi
  fi

  if [ -n "${TGDB_DIR:-}" ]; then
    local tgdb_resolved
    tgdb_resolved="$(readlink -f -- "$TGDB_DIR" 2>/dev/null || printf '%s' "$TGDB_DIR")"
    if [ "$resolved" = "$tgdb_resolved" ]; then
      return 1
    fi
  fi

  return 0
}

_gameserver_prompt_delete_volume_dir() {
  local volume_dir="$1" out_var="$2"
  local should_delete="0"

  if [ ! -d "$volume_dir" ]; then
    printf -v "$out_var" '%s' "$should_delete"
    return 0
  fi

  if ! _gameserver_is_safe_delete_path "$volume_dir"; then
    tgdb_warn "安全保護：此路徑不允許自動刪除：$volume_dir"
    tgdb_warn "如需清理請手動確認後執行。"
    printf -v "$out_var" '%s' "$should_delete"
    return 0
  fi

  if ui_confirm_yn "是否同時刪除備份目錄（$volume_dir）？(y/N，預設 Y，輸入 0 取消): " "Y"; then
    should_delete="1"
  else
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      return 2
    fi
  fi

  printf -v "$out_var" '%s' "$should_delete"
  return 0
}

_gameserver_try_delete_volume_dir() {
  local volume_dir="$1"

  [ -n "$volume_dir" ] || return 0
  [ -d "$volume_dir" ] || return 0

  if ! _gameserver_is_safe_delete_path "$volume_dir"; then
    tgdb_warn "安全保護：拒絕刪除非預期路徑：$volume_dir"
    return 1
  fi

  if command -v podman >/dev/null 2>&1; then
    if ! podman unshare rm -rf -- "$volume_dir" 2>/dev/null; then
      if ! rm -rf -- "$volume_dir" 2>/dev/null && [ -d "$volume_dir" ]; then
        tgdb_warn "無法刪除遊戲資料目錄：$volume_dir"
        tgdb_warn "可能因權限不足，請使用 sudo 或 root 手動清理。"
        return 1
      fi
    fi
  else
    if ! rm -rf -- "$volume_dir" 2>/dev/null && [ -d "$volume_dir" ]; then
      tgdb_warn "無法刪除遊戲資料目錄：$volume_dir"
      tgdb_warn "可能因權限不足，請使用 sudo 或 root 手動清理。"
      return 1
    fi
  fi

  echo "✅ 已刪除遊戲資料目錄：$volume_dir"
  return 0
}

_gameserver_unit_action() {
  local action="$1" unit_base="$2"

  _gameserver_ensure_podman_helpers || return 1

  case "$action" in
    start)
      _unit_try_enable_now "${unit_base}.container"
      return $?
      ;;
    stop)
      _unit_try_stop "${unit_base}.container"
      return $?
      ;;
    restart)
      _unit_try_restart "${unit_base}.container"
      return $?
      ;;
    *)
      tgdb_fail "不支援的單元操作：$action" 2 || true
      return 2
      ;;
  esac
}

gameserver_p_start() {
  _gameserver_require_tty || return $?

  local unit_base=""
  _gameserver_select_unit_base unit_base "啟動伺服器" || return 0

  if _gameserver_unit_action "start" "$unit_base"; then
    echo "✅ 已送出啟動：$unit_base（啟動中，可用日誌觀察）"
  else
    tgdb_warn "啟動失敗：$unit_base（請查看日誌）"
  fi
  ui_pause "按任意鍵返回..."
  return 0
}

gameserver_p_stop() {
  _gameserver_require_tty || return $?

  local unit_base=""
  _gameserver_select_unit_base unit_base "停止伺服器" || return 0

  if _gameserver_unit_action "stop" "$unit_base"; then
    echo "✅ 已停止：$unit_base"
  else
    tgdb_warn "停止失敗：$unit_base（請查看日誌）"
  fi
  ui_pause "按任意鍵返回..."
  return 0
}

gameserver_p_restart() {
  _gameserver_require_tty || return $?

  local unit_base=""
  _gameserver_select_unit_base unit_base "重啟伺服器" || return 0

  if _gameserver_unit_action "restart" "$unit_base"; then
    echo "✅ 已送出重啟：$unit_base（啟動中，可用日誌觀察）"
  else
    tgdb_warn "重啟失敗：$unit_base（請查看日誌）"
  fi
  ui_pause "按任意鍵返回..."
  return 0
}

gameserver_p_logs() {
  _gameserver_require_tty || return $?
  _gameserver_ensure_podman_helpers || { ui_pause "按任意鍵返回..."; return 1; }

  local unit_base=""
  _gameserver_select_unit_base unit_base "查看伺服器日誌" || return 0

  # 對齊 Podman 管理「查看單元日誌」行為：直接追蹤 systemd --user 單元日誌。
  if declare -F _unit_try_logs_follow >/dev/null 2>&1; then
    if _unit_try_logs_follow "${unit_base}.container"; then
      return 0
    fi
    if _unit_try_logs_follow "$unit_base"; then
      return 0
    fi
  fi

  tgdb_warn "無法套用 Podman 單元日誌流程，請到 Podman 管理 -> 查看單元日誌 直接確認。"
  ui_pause "按任意鍵返回..."
  return 0
}

_gameserver_prompt_lgsm_command() {
  local out_var="$1"
  local cmd=""

  while true; do
    clear
    echo "=================================="
    echo "❖ LinuxGSM 維運命令 ❖"
    echo "=================================="
    echo "1. details"
    echo "2. monitor"
    echo "3. update-lgsm"
    echo "4. update"
    echo "5. send"
    echo "6. backup"
    echo "7. console"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-7]: " cmd

    case "$cmd" in
      1) printf -v "$out_var" '%s' "details"; return 0 ;;
      2) printf -v "$out_var" '%s' "monitor"; return 0 ;;
      3) printf -v "$out_var" '%s' "update-lgsm"; return 0 ;;
      4) printf -v "$out_var" '%s' "update"; return 0 ;;
      5) printf -v "$out_var" '%s' "send"; return 0 ;;
      6) printf -v "$out_var" '%s' "backup"; return 0 ;;
      7) printf -v "$out_var" '%s' "console"; return 0 ;;
      0) return 1 ;;
      *) echo "無效選項"; sleep 1 ;;
    esac
  done
}

_gameserver_prompt_manual_shortname() {
  local out_var="$1"
  local input_shortname=""
  while true; do
    read -r -e -p "找不到 shortname 紀錄，請手動輸入 shortname（輸入 0 取消）: " input_shortname
    if [ "$input_shortname" = "0" ]; then
      return 2
    fi
    input_shortname="${input_shortname,,}"
    if _gameserver_is_valid_shortname "$input_shortname"; then
      printf -v "$out_var" '%s' "$input_shortname"
      return 0
    fi
    tgdb_err "shortname 格式不正確，僅允許小寫英數與連字號（-）。"
  done
}

_gameserver_prompt_lgsm_send_payload() {
  local out_var="$1"
  local payload=""

  while true; do
    read -r -e -p "請輸入要送到遊戲主控台的內容（例：say hello，輸入 0 取消）: " payload
    if [ "$payload" = "0" ]; then
      return 2
    fi

    payload="$(_gameserver_trim_ws "$payload")"
    if [ -n "$payload" ]; then
      printf -v "$out_var" '%s' "$payload"
      return 0
    fi

    tgdb_err "送出內容不可為空，請重新輸入。"
  done
}

_gameserver_exec_lgsm_command() {
  local unit_base="$1" shortname="$2" command_name="$3" command_arg="${4:-}"
  local container_name server_script

  container_name="$(_gameserver_container_name_from_unit_base "$unit_base")"
  server_script="${shortname}server"

  if ! podman ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container_name"; then
    tgdb_fail "找不到容器：$container_name（請先部署或檢查單元狀態）。" 1 || true
    return 1
  fi

  case "$command_name" in
    send)
      echo "執行命令：podman exec --user linuxgsm $container_name ./${server_script} send \"...\""
      echo "----------------------------------"
      podman exec --user linuxgsm "$container_name" "./${server_script}" "send" "$command_arg"
      return $?
      ;;
    console)
      echo "執行命令：podman exec -it --user linuxgsm $container_name ./${server_script} console"
      echo "提示：接下來若出現 Continue? [Y/n]，請輸入 Y。"
      echo "提示：離開 console 請按 Ctrl+b，接著按 d。"
      echo "----------------------------------"
      podman exec -it --user linuxgsm "$container_name" "./${server_script}" "console"
      return $?
      ;;
    *)
      echo "執行命令：podman exec --user linuxgsm $container_name ./${server_script} ${command_name}"
      echo "----------------------------------"
      podman exec --user linuxgsm "$container_name" "./${server_script}" "$command_name"
      return $?
      ;;
  esac
}

gameserver_p_lgsm_menu() {
  _gameserver_require_tty || return $?
  _gameserver_require_podman || { ui_pause "按任意鍵返回..."; return 1; }

  local unit_base=""
  _gameserver_select_unit_base unit_base "LinuxGSM 維運命令" || return 0

  local shortname=""
  shortname="$(_gameserver_shortname_of_unit "$unit_base" 2>/dev/null || true)"
  if ! _gameserver_is_valid_shortname "$shortname"; then
    _gameserver_prompt_manual_shortname shortname || {
      local rc=$?
      if [ "$rc" -eq 2 ]; then
        echo "操作已取消。"
        return 0
      fi
      return "$rc"
    }
  fi

  local command_name=""
  _gameserver_prompt_lgsm_command command_name || return 0

  local command_arg=""
  if [ "$command_name" = "send" ]; then
    _gameserver_prompt_lgsm_send_payload command_arg || {
      local rc=$?
      if [ "$rc" -eq 2 ]; then
        echo "操作已取消。"
        return 0
      fi
      return "$rc"
    }
  fi

  if ! _gameserver_exec_lgsm_command "$unit_base" "$shortname" "$command_name" "$command_arg"; then
    tgdb_warn "LinuxGSM 命令執行失敗：$command_name"
  fi
  ui_pause "按任意鍵返回..."
  return 0
}

gameserver_p_remove() {
  _gameserver_require_tty || return $?

  local unit_base=""
  _gameserver_select_unit_base unit_base "移除伺服器單元" || return 0

  _gameserver_ensure_podman_helpers || { ui_pause "按任意鍵返回..."; return 1; }

  local volume_dir="" delete_volume="0"
  volume_dir="$(_gameserver_volume_dir_of_unit "$unit_base" 2>/dev/null || true)"
  if [ -n "$volume_dir" ]; then
    _gameserver_prompt_delete_volume_dir "$volume_dir" delete_volume || {
      local rc=$?
      if [ "$rc" -eq 2 ]; then
        echo "操作已取消。"
        return 0
      fi
      return "$rc"
    }
  fi

  local unit_file
  unit_file="$(_gameserver_unit_path "$unit_base")"

  if _remove_quadlet_unit "${unit_base}.container"; then
    if [ "$delete_volume" = "1" ]; then
      _gameserver_try_delete_volume_dir "$volume_dir" || true
    fi
    if [ ! -f "$unit_file" ]; then
      _gameserver_remove_records "$unit_base"
      echo "✅ 已同步清理 metadata 紀錄：$unit_base"
    fi
  else
    tgdb_warn "移除失敗：$unit_base"
  fi

  ui_pause "按任意鍵返回..."
  return 0
}

gameserver_p_edit_unit() {
  _gameserver_require_tty || return $?

  local unit_base=""
  _gameserver_select_unit_base unit_base "編輯伺服器單元" || return 0

  local unit_file
  unit_file="$(_gameserver_unit_path "$unit_base")"
  if [ ! -f "$unit_file" ]; then
    tgdb_fail "找不到可編輯的單元檔：$unit_file" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  if ! ensure_editor; then
    tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "提示：可在單元內調整 Network / PublishPort / 其他參數。"
  echo "完成編輯後會自動 daemon-reload 並重啟單元。"
  echo "----------------------------------"
  "$EDITOR" "$unit_file"

  _systemctl_user_try daemon-reload || true
  if _gameserver_unit_action "restart" "$unit_base"; then
    echo "✅ 已套用變更並送出重啟：$unit_base"
  else
    tgdb_warn "重啟失敗：$unit_base（請查看日誌）"
  fi

  _gameserver_write_record_quadlet "$unit_base" "$(cat "$unit_file" 2>/dev/null || true)"
  echo "✅ 已同步單元紀錄：$(_gameserver_record_quadlet_path "$unit_base")"

  ui_pause "按任意鍵返回..."
  return 0
}
