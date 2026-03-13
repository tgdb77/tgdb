#!/bin/bash

# Kopia 管理：部署
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_MENU_DEPLOY_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_MENU_DEPLOY_LOADED=1

kopia_p_deploy() {
  _kopia_require_interactive || return $?
  load_system_config >/dev/null 2>&1 || true

  if ! _ensure_podman_version_for_quadlet; then
    return 1
  fi

  if _kopia_is_installed; then
    tgdb_warn "偵測到已部署 Kopia（kopia）。若要重裝請先使用「完全移除」或手動移除單元/容器。"
    ui_pause "按任意鍵返回..."
    return 0
  fi

  local default_port host_port
  default_port="$(get_next_available_port 51115 2>/dev/null || echo 51115)"
  host_port="$(prompt_available_port "對外埠（Web UI）" "$default_port")" || {
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "操作已取消。"
      return 0
    fi
    return 1
  }

  local name="kopia"
  local instance_dir
  instance_dir="$TGDB_DIR/$name"
  echo "資料目錄：$instance_dir"

  local propagation selinux_flag
  read -r propagation selinux_flag <<< "$(_apps_default_mount_options "$instance_dir" 2>/dev/null || echo "none none")"

  _deploy_app_core "kopia" "$name" "$host_port" "$instance_dir" "$propagation" "$selinux_flag" || return $?

  echo "⏳ 已完成部署，接續進行遠端 Repository 設定..."
  kopia_p_setup_remote_repository
  return $?
}
