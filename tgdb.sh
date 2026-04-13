#!/bin/bash

set -euo pipefail
# TGDB 主入口腳本

if [ -L "$0" ]; then
  REAL_SCRIPT_PATH=$(readlink -f "$0")
  SCRIPT_DIR="$(dirname "$REAL_SCRIPT_PATH")"
  # shellcheck disable=SC2034 # 供其他模組（例如 src/system.sh）使用
  SCRIPT_PATH="$REAL_SCRIPT_PATH"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC2034 # 供其他模組（例如 src/system.sh）使用
  SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$SCRIPT_DIR/tgdb.sh")"
fi

TGDB_ROOT_DIR="$SCRIPT_DIR"
SRC_DIR="$TGDB_ROOT_DIR/src"

env_setup_run_cli() {
  if ! declare -F cli_entry >/dev/null 2>&1; then
    if declare -F tgdb_fail >/dev/null 2>&1; then
      tgdb_fail "找不到 CLI 入口函式 cli_entry，請檢查 src/core/cli.sh 是否已載入。" 1 || true
    else
      echo "❌ 找不到 CLI 入口函式 cli_entry，請檢查 src/core/cli.sh 是否已載入。"
    fi
    return 1
  fi

  local old_cli_mode_set=0
  local old_cli_mode=""
  if [ "${TGDB_CLI_MODE+x}" = "x" ]; then
    old_cli_mode_set=1
    old_cli_mode="$TGDB_CLI_MODE"
  fi

  local old_internal_set=0
  local old_internal=""
  if [ "${TGDB_INTERNAL+x}" = "x" ]; then
    old_internal_set=1
    old_internal="$TGDB_INTERNAL"
  fi

  export TGDB_CLI_MODE=1
  export TGDB_INTERNAL=1
  ( set +u; cli_entry "$@" )
  local status=$?

  if [ "$old_cli_mode_set" -eq 1 ]; then
    export TGDB_CLI_MODE="$old_cli_mode"
  else
    unset TGDB_CLI_MODE
  fi

  if [ "$old_internal_set" -eq 1 ]; then
    export TGDB_INTERNAL="$old_internal"
  else
    unset TGDB_INTERNAL
  fi

  return "$status"
}

# 檢查模組是否存在
check_modules() {
  local required_modules=(
    "core/bootstrap.sh"
    "core/utils.sh"
    "core/routes.sh"
    "core/cli.sh"
    "system.sh"
  )

  # 僅檢查入口啟動必需的核心檔案；
  # 其餘功能模組改由 routes 的動態載入機制在實際使用時檢查。

  local missing_modules=()
  local module

  for module in "${required_modules[@]}"; do
    if [ ! -f "$SRC_DIR/$module" ]; then
      missing_modules+=("$module")
    fi
  done

  if [ ${#missing_modules[@]} -gt 0 ]; then
    echo "❌ 錯誤：缺少必要的模組檔案："
    for module in "${missing_modules[@]}"; do
      echo "   - $SRC_DIR/$module"
    done
    echo ""
    echo "請確認您在正確的 TGDB 目錄執行，且 src/ 目錄完整。"
    echo "若是 git 倉庫，建議先執行："
    echo "  git status"
    echo "  git pull --ff-only"
    return 1
  fi
}

# 載入模組
load_modules() {
  local force="${1:-}"
  check_modules || return 1

  # shellcheck source=/dev/null
  if [ "$force" = "--force" ]; then
    export TGDB_FORCE_RELOAD_LIBS=1
  fi

  source "$SRC_DIR/core/bootstrap.sh"
  if [ -f "$SRC_DIR/core/routes.sh" ]; then
    # shellcheck source=/dev/null
    source "$SRC_DIR/core/routes.sh"
    # 清除模組快取：避免「更新後」仍沿用已載入的舊模組內容
    if declare -F tgdb_reset_module_cache >/dev/null 2>&1; then
      tgdb_reset_module_cache
    fi
  fi
  if [ -f "$SRC_DIR/core/cli.sh" ]; then
    # shellcheck source=/dev/null
    source "$SRC_DIR/core/cli.sh"
  fi
  if [ -f "$SRC_DIR/system.sh" ]; then
    # shellcheck source=src/system.sh
    source "$SRC_DIR/system.sh"
  fi
  if [ "$force" = "--force" ]; then
    unset TGDB_FORCE_RELOAD_LIBS 2>/dev/null || true
    # 記錄本次為強制重載：後續透過 tgdb_load_module 載入的模組也需要一併重載，
    # 避免「更新後」因各模組的載入守衛而沿用舊版本函式定義。
    export TGDB_FORCE_RELOAD_MODULES=1
  fi

  # 不在執行時強制 chmod，避免在只讀或權限不足環境造成整體失敗
  if [ "${TGDB_CLI_MODE:-0}" = "1" ]; then
    return 0
  fi

  echo "✅ 所有模組已載入"
}

# 更新 TGDB 程式碼與模組
update_tgdb() {
    clear
    echo "=================================="
    echo "❖ 更新 TGDB 系統 ❖"
    echo "=================================="
    
    local repo_dir
    repo_dir="$TGDB_ROOT_DIR"

    if [ -d "$repo_dir/.git" ]; then
        if ! command -v git >/dev/null 2>&1; then
            tgdb_fail "系統未安裝 git，無法自動更新。" 1 || true
            return 1
        fi

        local branch
        branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

        if [ "$branch" != "main" ]; then
            if [ "$branch" = "HEAD" ] || [ -z "$branch" ]; then
                tgdb_fail "目前為 detached HEAD 狀態，為避免更新到不預期版本，已停止自動更新。" 1 || true
            else
                tgdb_fail "目前分支為 '$branch'，本功能僅允許更新 main 分支。" 1 || true
            fi
            echo "請先切換到 main 後再更新："
            echo "  git switch main"
            return 1
        fi

        if ! git -C "$repo_dir" remote get-url origin >/dev/null 2>&1; then
            tgdb_fail "找不到 git remote：origin，無法自動更新。" 1 || true
            return 1
        fi

        if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
            tgdb_warn "偵測到未提交變更。"
            echo "若繼續強制覆蓋，將捨棄目前已追蹤檔案的未提交修改。"
            echo "即將執行：git reset --hard HEAD"
            if ! ui_confirm_yn "是否強制覆蓋本機變更後繼續更新？(y/N，預設 N，輸入 0 取消): " "N"; then
                echo "已取消更新，請先提交或還原變更後再更新。"
                return 1
            fi

            if ! git -C "$repo_dir" reset --hard HEAD; then
                tgdb_fail "強制覆蓋本機變更失敗，已停止更新。" 1 || true
                return 1
            fi
        fi

        echo "正在從 Git 倉庫更新 main（僅允許 fast-forward）..."
        if git -C "$repo_dir" pull --ff-only origin main; then
            echo "✅ TGDB 系統已更新"
            echo "重新載入模組..."
            load_modules --force
        else
            tgdb_fail "更新失敗" 1 || true
            echo "可能原因：本機版本與遠端分歧（需要合併）、或遠端不可用。"
            echo "建議先執行：git status / git remote -v / git fetch"
        fi
    else
        echo "此安裝目錄不是從 Git 倉庫安裝的，無法自動更新：$repo_dir"
        echo "請手動下載最新版本。"
    fi
    
    ui_pause "按任意鍵返回..." "main"
}

# 主選單：路由至各管理模組
main_menu() {
  while true; do
    clear
    echo "=================================="
    echo "❖ TGDB 管理系統 ❖"
    echo "=================================="

    if ! declare -F tgdb_print_main_menu >/dev/null 2>&1; then
      tgdb_fail "找不到共用路由表（src/core/routes.sh），請先更新或重新安裝 TGDB。" 1 || true
      ui_pause "按任意鍵返回..." "main"
      return 1
    fi
    tgdb_print_main_menu

    echo "=================================="
    read -r -e -p "請輸入選擇: " main_choice

    if ! declare -F tgdb_dispatch_main_menu >/dev/null 2>&1; then
      tgdb_fail "找不到主選單路由器（src/core/routes.sh），請先更新或重新安裝 TGDB。" 1 || true
      ui_pause "按任意鍵返回..." "main"
      return 1
    fi

    if declare -F tgdb_clear_last_error >/dev/null 2>&1; then
      tgdb_clear_last_error
    fi
    tgdb_dispatch_main_menu "$main_choice"
    local rc=$?
    case "$rc" in
      0) ;;
      "${TGDB_RC_EXIT:-100}")
        clear || true
        echo "感謝使用 TGDB 管理系統！"
        return 0
        ;;
      3)
        echo "無效選項，請重新輸入。"
        sleep 1
        ;;
      *)
        if declare -F tgdb_print_last_error >/dev/null 2>&1; then
          tgdb_print_last_error || true
        fi
        ui_pause "按任意鍵返回..." "main"
        ;;
    esac
  done
}

# 入口函式：初始化並啟動主選單
main() {
  # 互動模式請明確關閉 CLI 模式，避免使用者環境變數殘留導致判斷錯誤
  if [ "$#" -gt 0 ]; then
    export TGDB_CLI_MODE=1
  else
    export TGDB_CLI_MODE=0
    if [ ! -t 0 ]; then
      echo "❌ 偵測到非互動終端（stdin 不是 TTY），請改用 CLI 模式執行（例如：./tgdb.sh -h）。" >&2
      return 2
    fi
  fi

  load_modules || return 1

  if declare -F tgdb_check_entry_dependencies >/dev/null 2>&1; then
    tgdb_check_entry_dependencies || return $?
  fi

  if [ "$#" -gt 0 ]; then
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
      if declare -F cli_entry >/dev/null 2>&1; then
        ( set +u; cli_entry "$@" ) || true
        return 0
      fi
      tgdb_fail "找不到 CLI 入口函式 cli_entry，請檢查 src/core/cli.sh 是否已載入。" 1 || true
      return 1
    fi
  fi

  load_system_config
  create_tgdb_dir

  if [ "${TGDB_CLI_MODE:-0}" = "0" ] && declare -F ensure_default_shortcut_t >/dev/null 2>&1; then
    ensure_default_shortcut_t || true
  fi

  if [ "$#" -gt 0 ]; then
    if declare -F cli_entry >/dev/null 2>&1; then
      ( set +u; cli_entry "$@" )
      return $?
    else
      tgdb_fail "CLI 模組缺少入口函式 cli_entry，請檢查 src/core/cli.sh。" 1 || true
      return 1
    fi
  fi

  main_menu
}

if main "$@"; then
  exit 0
else
  rc=$?
  if declare -F tgdb_print_last_error >/dev/null 2>&1; then
    tgdb_print_last_error || true
  fi
  exit "$rc"
fi
