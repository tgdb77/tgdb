#!/bin/bash

# Kopia 管理：主程式更新
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_MENU_UPDATE_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_MENU_UPDATE_LOADED=1

KOPIA_IMAGE_LATEST="docker.io/kopia/kopia:latest"

_kopia_detect_deploy_mode() {
  _apps_detect_instance_deploy_mode "kopia" "kopia" 2>/dev/null || printf '%s\n' "$(_apps_current_deploy_mode 2>/dev/null || echo rootless)"
}

_kopia_update_unit_image_to_latest() {
  local deploy_mode="$1" unit_path="$2"
  local content updated

  content="$(_apps_read_file "$deploy_mode" "$unit_path" 2>/dev/null || true)"
  if [ -z "$content" ]; then
    tgdb_fail "無法讀取 Kopia Quadlet 單元：$unit_path" 1 || return $?
    return 1
  fi

  if ! printf '%s\n' "$content" | grep -q '^Image=docker\.io/kopia/kopia:'; then
    tgdb_fail "Kopia Quadlet 內找不到可更新的 Image=docker.io/kopia/kopia:* 設定。" 1 || return $?
    return 1
  fi

  updated="$(printf '%s\n' "$content" | sed -E "s|^Image=docker\\.io/kopia/kopia:[^[:space:]]+$|Image=${KOPIA_IMAGE_LATEST}|")"
  _apps_write_text_file "$deploy_mode" "$unit_path" "$updated" || {
    tgdb_fail "無法寫入 Kopia Quadlet 單元：$unit_path" 1 || return $?
    return 1
  }
}

kopia_p_update_main_program() {
  _kopia_require_interactive || return $?
  load_system_config >/dev/null 2>&1 || true

  if ! _kopia_is_installed; then
    tgdb_fail "尚未部署 Kopia，請先執行部署。" 1 || true
    ui_pause "按任意鍵返回..."
    return 0
  fi

  echo "❖ Kopia 主程式更新 ❖"
  echo "此功能會將已部署的 Kopia Quadlet 映像改為：$KOPIA_IMAGE_LATEST"
  echo "並拉取最新映像、重載 systemd、重啟 Kopia 容器。"

  if ! ui_confirm_yn "確定要更新 Kopia 主程式嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "操作已取消。"
    fi
    ui_pause "按任意鍵返回..."
    return 0
  fi

  local deploy_mode unit_path scope
  deploy_mode="$(_kopia_detect_deploy_mode)"

  unit_path="$(_apps_with_deploy_mode "$deploy_mode" _kopia_resolved_unit_path)"
  if ! _apps_path_exists "$deploy_mode" "$unit_path"; then
    tgdb_fail "找不到 Kopia Quadlet 單元：$unit_path" 1 || true
    ui_pause "按任意鍵返回..."
    return 0
  fi

  echo "⏳ 正在更新 Quadlet 映像設定..."
  _kopia_update_unit_image_to_latest "$deploy_mode" "$unit_path" || {
    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "⏳ 正在拉取最新 Kopia 映像..."
  _apps_with_deploy_mode "$deploy_mode" tgdb_podman pull "$KOPIA_IMAGE_LATEST" || {
    tgdb_fail "拉取 Kopia 映像失敗，請檢查網路或 registry 狀態。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  }

  scope="$(_apps_scope_for_mode "$deploy_mode" 2>/dev/null || echo user)"
  echo "⏳ 正在重載 systemd 並重啟 Kopia..."
  tgdb_systemctl_try "$scope" daemon-reload >/dev/null 2>&1 || true
  if ! _apps_with_deploy_mode "$deploy_mode" _app_restart_units_by_filenames "kopia.container"; then
    tgdb_fail "重啟 Kopia 失敗，請檢查 systemd 與 Podman 日誌。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "🧹 更新成功，正在清理無標籤的舊映像..."
  _apps_with_deploy_mode "$deploy_mode" tgdb_podman image prune -f || tgdb_warn "舊映像清理失敗，請稍後從 Podman 管理選單重試。"
  echo "✅ Kopia 主程式已更新。"
  ui_pause "按任意鍵返回..."
}
