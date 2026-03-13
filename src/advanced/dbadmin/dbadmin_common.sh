#!/bin/bash

# 數據庫管理：共用工具
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_COMMON_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_COMMON_LOADED=1

_dbadmin_require_interactive() {
  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi
  return 0
}

_dbadmin_pick_tool() {
  local __outvar="$1"
  local title="${2:-選擇目標}"
  local prompt="${3:-請選擇要操作的管理工具：}"
  [ -n "${__outvar:-}" ] || return 1

  while true; do
    clear
    echo "=================================="
    echo "❖ 數據庫管理：$title ❖"
    echo "=================================="
    echo "$prompt"
    echo "----------------------------------"

    local s1 s2
    s1="pgAdmin（$(_dbadmin_podman_container_status_label "pgadmin")）"
    s2="RedisInsight（$(_dbadmin_podman_container_status_label "redisinsight")）"

    echo "1. $s1"
    echo "2. $s2"
    echo "----------------------------------"
    echo "0. 取消"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-2]: " choice

    case "$choice" in
      1) printf -v "$__outvar" '%s' "pgadmin"; return 0 ;;
      2) printf -v "$__outvar" '%s' "redisinsight"; return 0 ;;
      0) return 2 ;;
      *) echo "無效選項，請重新輸入。"; sleep 1 ;;
    esac
  done
}

_dbadmin_is_tool_installed() {
  local service="$1" name="$2"
  [ -z "$service" ] && return 1
  [ -z "$name" ] && return 1

  local unit_path
  unit_path="$(rm_user_units_dir)/${name}.container"
  if [ -f "$unit_path" ]; then
    return 0
  fi

  if command -v podman >/dev/null 2>&1; then
    if podman ps -aq --filter "label=app=${service}" 2>/dev/null | head -n1 | grep -q .; then
      return 0
    fi
  fi

  return 1
}

_dbadmin_podman_container_status_label() {
  local name="$1"

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

_dbadmin_print_runtime_status() {
  local pg_label ri_label
  pg_label="$(_dbadmin_podman_container_status_label "pgadmin")"
  ri_label="$(_dbadmin_podman_container_status_label "redisinsight")"

  echo "狀態："
  echo " - pgAdmin：$pg_label"
  echo " - RedisInsight：$ri_label"
  return 0
}

_dbadmin_is_instance_name_conflict() {
  local name="$1"
  [ -z "$name" ] && return 1

  local user_units_dir
  user_units_dir="$(rm_user_units_dir)"
  if [ -d "$user_units_dir" ]; then
    if [ -f "$user_units_dir/$name.container" ] || \
       [ -f "$user_units_dir/$name.service" ] || \
       [ -f "$user_units_dir/container-$name.service" ]; then
      return 0
    fi
  fi

  local persist_dir
  persist_dir="$(rm_persist_config_dir 2>/dev/null || echo "")"
  if [ -n "${persist_dir:-}" ] && [ -d "$persist_dir" ]; then
    if find "$persist_dir" -maxdepth 4 -type f \( \
        -path "*/quadlet/$name.container" -o \
        -path "*/configs/$name.*" \
      \) -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  fi

  if command -v podman >/dev/null 2>&1; then
    if podman container exists "$name" 2>/dev/null; then
      return 0
    fi
  fi

  return 1
}

_dbadmin_pick_default_mount_options() {
  local instance_dir="$1"
  local propagation="none" selinux_flag="none"

  local mount_out="" mount_line="" line=""
  mount_out="$(_apps_default_mount_options "$instance_dir")" || true
  while IFS= read -r line; do
    [ -n "$line" ] && mount_line="$line"
  done <<< "$mount_out"
  if [ -n "$mount_line" ]; then
    IFS=' ' read -r propagation selinux_flag <<< "$mount_line"
  fi

  printf '%s %s\n' "$propagation" "$selinux_flag"
}
