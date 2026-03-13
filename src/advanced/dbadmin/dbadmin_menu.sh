#!/bin/bash

# 數據庫管理：主選單
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_MENU_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_MENU_LOADED=1

dbadmin_p_menu() {
  _dbadmin_require_interactive || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ 數據庫管理 ❖"
    echo "教學與文件：pgAdmin：https://www.pgadmin.org/docs/ ｜ RedisInsight：https://redis.io/docs/latest/operate/redisinsight/"
    echo "=================================="
    _dbadmin_print_runtime_status || true
    echo "----------------------------------"
    echo "1. 部署 pgAdmin 4（PostgreSQL Web 管理）"
    echo "2. 部署 RedisInsight（Redis Web 管理）"
    echo "----------------------------------"
    echo "3. 匯出（熱備份）：PostgreSQL / Redis / MySQL"
    echo "4. 匯入（覆蓋還原）：PostgreSQL / Redis / MySQL"
    echo "5. 批次匯出：自動偵測全部 DB"
    echo "6. 批次匯入：自動偵測全部 DB（最新備份覆蓋）"
    echo "7. 定時備份：日/週/月（批次匯出）"
    echo "8. 更新 Web 管理工具（拉新映像並重啟）"
    echo "----------------------------------"
    echo "9. 完全移除"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-8,9]: " choice

    case "$choice" in
      1)
        _dbadmin_deploy_single_instance "pgadmin" "pgadmin" 15050 || true
        ;;
      2)
        _dbadmin_deploy_single_instance "redisinsight" "redisinsight" 15540 || true
        ;;
      3)
        dbbackup_p_export_menu || true
        ;;
      4)
        dbbackup_p_import_menu || true
        ;;
      5)
        dbbackup_p_export_all_menu || true
        ;;
      6)
        dbbackup_p_import_all_latest_menu || true
        ;;
      7)
        _dbadmin_dbbackup_timers_menu || true
        ;;
      8)
        _dbadmin_update_pick_and_run || true
        ;;
      9)
        local picked="" rc=0
        _dbadmin_full_remove_pick picked || rc=$?
        if [ "$rc" -ne 0 ]; then
          [ "$rc" -eq 2 ] && echo "操作已取消。" && sleep 1
          continue
        fi
        case "$picked" in
          pgadmin) _dbadmin_full_remove_single "pgadmin" "pgadmin" || true ;;
          redisinsight) _dbadmin_full_remove_single "redisinsight" "redisinsight" || true ;;
        esac
        ;;
      0)
        return 0
        ;;
      *)
        echo "無效選項，請重新輸入。"
        sleep 1
        ;;
    esac
  done
}
