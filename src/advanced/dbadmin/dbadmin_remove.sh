#!/bin/bash

# 數據庫管理：完全移除
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_REMOVE_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_REMOVE_LOADED=1

_dbadmin_full_remove_pick() {
  local __outvar="$1"
  [ -n "${__outvar:-}" ] || return 1
  _dbadmin_pick_tool "$__outvar" "完全移除" "請選擇要移除的管理工具："
}

_dbadmin_full_remove_single() {
  local service="$1" name="$2"
  [ -n "$service" ] || return 1
  [ -n "$name" ] || return 1

  _dbadmin_require_interactive || return $?

  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法執行完全移除。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local delete_flag="1"
  if ui_confirm_yn "是否同時刪除實例資料夾（$TGDB_DIR/$name）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    delete_flag="0"
  else
    local r2=$?
    if [ "$r2" -eq 2 ]; then
      echo "操作已取消。"
      return 0
    fi
    delete_flag="1"
  fi

  local image
  image="$(_apps_service_default_image "$service" 2>/dev/null || echo "")"
  _full_remove_instance "$service" "$image" "$name" "$delete_flag"
}
