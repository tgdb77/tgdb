#!/bin/bash

# Kopia 管理：共用函式
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_KOPIA_MENU_COMMON_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_KOPIA_MENU_COMMON_LOADED=1

_kopia_require_interactive() {
  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi
  return 0
}

_kopia_runner_script() {
  local script="${KOPIA_MODULE_DIR:-$KOPIA_DIR/kopia}/kopia-backup-cli.sh"
  if [ -f "$script" ]; then
    printf '%s\n' "$script"
    return 0
  fi
  printf '%s\n' "$KOPIA_DIR/kopia-backup.sh"
}

_kopia_rclone_config_file() {
  printf '%s\n' "$TGDB_DIR/rclone.conf"
}

_kopia_list_rclone_remotes() {
  local cfg
  cfg="$(_kopia_rclone_config_file)"
  [ -f "$cfg" ] || return 0
  if ! command -v rclone >/dev/null 2>&1; then
    return 1
  fi
  rclone listremotes --config "$cfg" 2>/dev/null | sed 's/:$//' | sed '/^$/d'
}

_kopia_resolved_unit_path() {
  _quadlet_runtime_or_legacy_unit_path "kopia.container" "kopia"
}

_kopia_is_installed() {
  local unit_path
  unit_path="$(_kopia_resolved_unit_path)"
  if [ -f "$unit_path" ]; then
    return 0
  fi

  if command -v podman >/dev/null 2>&1; then
    if podman ps -aq --filter "label=app=kopia" 2>/dev/null | head -n1 | grep -q .; then
      return 0
    fi
  fi

  return 1
}

_kopia_podman_container_status_label() {
  local name="${1:-kopia}"

  if ! command -v podman >/dev/null 2>&1; then
    echo "未知（缺少 podman）"
    return 0
  fi

  if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
    echo "✅ 執行中"
    return 0
  fi

  if podman ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
    echo "⏸ 已部署"
    return 0
  fi

  echo "❌ 未部署"
  return 0
}

_kopia_print_status() {
  echo "Kopia 容器：$(_kopia_podman_container_status_label "kopia")"

  local runner
  runner="$(_kopia_runner_script)"
  if [ -f "$runner" ]; then
    echo "----------------------------------"
    bash "$runner" status 2>/dev/null || true
  fi
}
