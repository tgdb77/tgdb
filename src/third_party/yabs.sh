#!/bin/bash

# 第三方腳本：YABS 綜合測試
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_THIRD_PARTY_YABS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_THIRD_PARTY_YABS_LOADED=1

third_party_run_yabs() {
  clear || true
  echo "=================================="
  echo "❖ YABS 綜合測試 ❖"
  echo "=================================="
  echo "即將執行：curl -sL https://yabs.sh | bash"
  echo ""

  if ! command -v curl >/dev/null 2>&1; then
    tgdb_fail "系統未安裝 curl，無法執行 YABS。請先到「基礎工具管理」安裝 curl。" 1 || true
    ui_pause "按任意鍵返回..." "main"
    return 1
  fi

  local rc=0
  ( set +e; set +o pipefail; curl -sL https://yabs.sh | bash -s -- -r -5 ) || rc=$?
  echo ""

  if [ "$rc" -eq 0 ]; then
    echo "✅ YABS 執行完成"
  else
    tgdb_warn "YABS 執行結束（返回碼：$rc），請自行檢查輸出是否完整。"
  fi

  ui_pause "執行完成，按任意鍵繼續..." "main"
  return 0
}
