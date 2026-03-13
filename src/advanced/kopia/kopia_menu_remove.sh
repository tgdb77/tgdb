#!/bin/bash

# Kopia 管理：完全移除
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_MENU_REMOVE_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_MENU_REMOVE_LOADED=1

kopia_p_full_remove() {
  _kopia_require_interactive || return $?
  load_system_config >/dev/null 2>&1 || true

  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法執行完全移除。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local runner
  runner="$(_kopia_runner_script)"

  if [ -f "$runner" ]; then
    if ui_confirm_yn "是否同時移除 Kopia 統一備份 timer（tgdb-kopia-backup.timer）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      bash "$runner" remove-timer || true
    else
      local trc=$?
      if [ "$trc" -eq 2 ]; then
        echo "操作已取消。"
        return 0
      fi
    fi
  fi

  local name="kopia"
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

  local service="kopia"
  local image
  image="$(_apps_service_default_image "$service" 2>/dev/null || echo "")"
  _full_remove_instance "$service" "$image" "$name" "$delete_flag"

  local ignore_file
  ignore_file="$TGDB_DIR/.kopiaignore"
  if [ -f "$ignore_file" ]; then
    if rm -f "$ignore_file" 2>/dev/null; then
      echo "✅ 已移除：$ignore_file"
    else
      tgdb_warn "無法移除：$ignore_file（請手動檢查權限）"
    fi
  fi
  return 0
}
