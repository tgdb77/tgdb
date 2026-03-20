#!/bin/bash

# 數據庫管理：部署工具
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DEPLOY_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DEPLOY_LOADED=1

_dbadmin_deploy_single_instance() {
  local service="$1" name="$2" base_port="$3"
  [ -n "$service" ] || return 1
  [ -n "$name" ] || return 1

  _dbadmin_require_interactive || return $?

  if ! _ensure_podman_version_for_quadlet; then
    return 1
  fi

  if _dbadmin_is_tool_installed "$service" "$name"; then
    tgdb_warn "偵測到已部署：$name。此工具不支援多次部署；若要重裝請先使用「完全移除」。"
    ui_pause "按任意鍵返回..."
    return 0
  fi

  if _dbadmin_is_instance_name_conflict "$name"; then
    tgdb_fail "已存在相同名稱：$name。請先移除/改名既有實例後再部署。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local default_port host_port
  default_port="$(get_next_available_port "$base_port" 2>/dev/null || echo "$base_port")"
  host_port="$(prompt_available_port "對外埠" "$default_port")" || {
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "操作已取消。"
      return 0
    fi
    return 1
  }

  local instance_dir
  instance_dir="$TGDB_DIR/$name"
  echo "資料目錄：$instance_dir"

  if [ -d "$instance_dir" ]; then
    local rc2=0
    ui_confirm_yn "偵測到資料目錄已存在，重新部署可能會覆蓋 $instance_dir/.env（以及部分檔案）。是否繼續？(Y/n，預設 N，輸入 0 取消): " "N" || rc2=$?
    if [ "$rc2" -ne 0 ]; then
      if [ "$rc2" -eq 2 ]; then
        echo "操作已取消。"
        return 0
      fi
      return 1
    fi
  fi

  local propagation selinux_flag
  read -r propagation selinux_flag <<< "$(_dbadmin_pick_default_mount_options "$instance_dir")"

  _deploy_app_core "$service" "$name" "$host_port" "$instance_dir" "$propagation" "$selinux_flag"
}

_dbadmin_update_single_instance() {
  local service="$1" name="$2"
  [ -n "$service" ] || return 1
  [ -n "$name" ] || return 1

  _dbadmin_require_interactive || return $?

  if ! _dbadmin_is_tool_installed "$service" "$name"; then
    tgdb_warn "尚未部署：$name，無法更新。請先完成部署後再試。"
    ui_pause "按任意鍵返回..."
    return 0
  fi

  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法拉取新映像並重啟。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local image
  image="$(_apps_service_default_image "$service" 2>/dev/null || echo "")"

  echo "更新方式：拉取最新映像並重新啟動，不會覆蓋既有資料與設定。"
  _service_update_and_restart "$service" "$image" "$name" "$image"
}

_dbadmin_update_pick_and_run() {
  local picked="" rc=0
  _dbadmin_pick_tool picked "更新 Web 管理工具" "請選擇要更新的管理工具：" || rc=$?
  if [ "$rc" -ne 0 ]; then
    [ "$rc" -eq 2 ] && echo "操作已取消。" && sleep 1
    return 0
  fi

  case "$picked" in
    pgadmin) _dbadmin_update_single_instance "pgadmin" "pgadmin" || true ;;
    redisinsight) _dbadmin_update_single_instance "redisinsight" "redisinsight" || true ;;
    cloudbeaver) _dbadmin_update_single_instance "cloudbeaver" "cloudbeaver" || true ;;
  esac
}
