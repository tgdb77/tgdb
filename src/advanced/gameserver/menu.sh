#!/bin/bash

# Game Server：互動菜單
# 注意：此檔案為 library，會被 source；請勿在此更改 shell options。

_gameserver_print_instances_overview() {
  local -a units=()
  local u
  while IFS= read -r u; do
    [ -n "$u" ] && units+=("$u")
  done < <(_gameserver_list_unit_bases)

  if [ ${#units[@]} -eq 0 ]; then
    echo "已部署實例： （尚無）"
    return 0
  fi

  echo "已部署實例："
  local idx=1
  for u in "${units[@]}"; do
    local instance_name shortname status
    instance_name="$(_gameserver_instance_name_from_unit_base "$u")"
    shortname="$(_gameserver_shortname_of_unit "$u" 2>/dev/null || echo "未知")"
    status="$(_gameserver_status_text "$(_gameserver_unit_status "$u")")"
    printf "  %2d. %-20s shortname=%-12s 狀態=%s\n" "$idx" "$instance_name" "$shortname" "$status"
    idx=$((idx + 1))
  done
}

gameserver_p_menu() {
  _gameserver_require_tty || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ Game Server（LinuxGSM）❖"
    echo "教學與文件：https://docs.linuxgsm.com/"
    echo "=================================="
    _gameserver_print_instances_overview
    echo "----------------------------------"
    echo "1. 新增/部署伺服器"
    echo "2. 啟動伺服器（單元）"
    echo "3. 停止伺服器（單元）"
    echo "4. 重啟伺服器（單元）"
    echo "5. 查看伺服器日誌"
    echo "6. LinuxGSM 維運命令"
    echo "7. 移除伺服器單元"
    echo "8. 編輯伺服器單元"
    echo "----------------------------------"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-8]: " choice

    case "$choice" in
      1) gameserver_p_deploy || true ;;
      2) gameserver_p_start || true ;;
      3) gameserver_p_stop || true ;;
      4) gameserver_p_restart || true ;;
      5) gameserver_p_logs || true ;;
      6) gameserver_p_lgsm_menu || true ;;
      7) gameserver_p_remove || true ;;
      8) gameserver_p_edit_unit || true ;;
      0) return 0 ;;
      *) echo "無效選項，請重新輸入。"; sleep 1 ;;
    esac
  done
}
