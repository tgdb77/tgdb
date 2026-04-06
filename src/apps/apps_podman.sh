#!/bin/bash

# Apps：Podman/掛載預設（由 src/apps-p.sh 載入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_ensure_podman_version_for_quadlet() {
  local marker
  marker="$TGDB_DIR/.tgdb_podman_quadlet_ok"

  if [ -n "$marker" ] && [ -f "$marker" ]; then
    return 0
  fi

  if ! command -v podman >/dev/null 2>&1; then
    local msg
    printf -v msg '%s\n%s\n\n%s\n%s\n%s\n%s' \
      "未偵測到 Podman，應用程式 Quadlet 佈署完全依賴 Podman。" \
      "請先安裝 Podman（建議 4.4 以上版本），可在主選單選擇「5. Podman 管理」執行安裝/更新。" \
      "推薦使用下列較新版本的 Linux 發行版以取得較新的 Podman：" \
      "- Debian 13 / Ubuntu 24.04 LTS" \
      "- Fedora 38+、CentOS Stream 9、Rocky Linux 9、AlmaLinux 9" \
      "- openSUSE Tumbleweed 等滾動發行版"
    tgdb_fail "$msg" 1 || true
    ui_pause "按任意鍵返回主選單..."
    return 1
  fi

  local ver_str major minor
  ver_str=$(podman --version 2>/dev/null | awk '{print $3}')

  if [ -z "$ver_str" ]; then
    local msg
    printf -v msg '%s\n%s' \
      "無法解析 Podman 版本字串，偵測結果：$(podman --version 2>/dev/null)" \
      "應用程式 Quadlet 佈署需要 Podman 4.4 以上版本，請確認套件來源是否提供足夠新的 Podman。"
    tgdb_fail "$msg" 1 || true
    ui_pause "按任意鍵返回主選單..."
    return 1
  fi

  ver_str=${ver_str%%-*}
  IFS='.' read -r major minor _ <<< "$ver_str"

  if [ -z "$major" ] || [ -z "$minor" ] || [[ ! "$major" =~ ^[0-9]+$ ]] || [[ ! "$minor" =~ ^[0-9]+$ ]]; then
    local msg
    printf -v msg '%s\n%s' \
      "無法解析 Podman 版本號：$ver_str" \
      "應用程式 Quadlet 佈署需要 Podman 4.4 以上版本，請確認套件來源是否提供足夠新的 Podman。"
    tgdb_fail "$msg" 1 || true
    ui_pause "按任意鍵返回主選單..."
    return 1
  fi

  if [ "$major" -gt 4 ] || { [ "$major" -eq 4 ] && [ "$minor" -ge 4 ]; }; then
    if [ -n "$marker" ]; then
      mkdir -p "$TGDB_DIR" 2>/dev/null || true
      touch "$marker" 2>/dev/null || true
    fi
    return 0
  fi

  local msg
  printf -v msg '%s\n%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
    "偵測到 Podman 版本過低：$ver_str" \
    "應用程式 Quadlet 佈署需要 Podman 4.4 以上版本。" \
    "請考慮以下方式升級 Podman：" \
    "1. 在主選單選擇「5. Podman 管理」→ 安裝/更新 Podman（若當前發行版提供足夠新版本）。" \
    "2. 選擇較新版本的 Linux 發行版，例如：" \
    "   - Debian 13 / Ubuntu 24.04 LTS" \
    "   - Fedora 38+、CentOS Stream 9、Rocky Linux 9、AlmaLinux 9" \
    "   - openSUSE Tumbleweed 等滾動發行版" \
    ""
  tgdb_fail "$msg" 1 || true
  ui_pause "按任意鍵返回主選單..."
  return 1
}

select_instance() {
  local service="$1"
  local _image="${2:-}"
  SELECTED_INSTANCE=""
  SELECTED_INSTANCE_MODE=""

  local instances=() instance_modes=()
  local seen=""
  local mode quad_dir runtime_dir

  local -a modes=()
  if declare -F _apps_service_supports_deploy_mode >/dev/null 2>&1; then
    _apps_service_supports_deploy_mode "$service" "rootless" && modes+=("rootless")
    _apps_service_supports_deploy_mode "$service" "rootful" && modes+=("rootful")
  fi
  [ ${#modes[@]} -gt 0 ] || modes=(rootless rootful)

  for mode in "${modes[@]}"; do
    quad_dir="$(rm_service_quadlet_dir_by_mode "$service" "$mode" 2>/dev/null || echo "")"
    if [ -n "$quad_dir" ] && _apps_dir_exists "$mode" "$quad_dir"; then
      local f=""
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        local b name
        b="${f##*/}"
        case "$b" in
          *.container) name="${b%.container}" ;;
          *.pod) name="${b%.pod}" ;;
          *) continue ;;
        esac
        if _app_is_aux_instance_name "$service" "$name"; then
          continue
        fi
        case ",$seen," in
          *,"$name",*) ;;
          *)
            instances+=("$name")
            instance_modes+=("$mode")
            seen="$seen,$name"
            ;;
        esac
      done < <(_apps_find_lines "$mode" "$quad_dir" -maxdepth 1 -type f \( -name "*.container" -o -name "*.pod" \) 2>/dev/null)
    fi

    runtime_dir="$(_apps_runtime_dir_for_mode "$mode" 2>/dev/null || echo "")"
    if [ -n "$runtime_dir" ] && _apps_dir_exists "$mode" "$runtime_dir"; then
      local d=""
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        local name
        name="$(basename "$d")"
        if _app_is_aux_instance_name "$service" "$name"; then
          continue
        fi
        case ",$seen," in
          *,"$name",*) ;;
          *)
            instances+=("$name")
            instance_modes+=("$mode")
            seen="$seen,$name"
            ;;
        esac
      done < <(_apps_find_lines "$mode" "$runtime_dir" -mindepth 1 -maxdepth 1 -type d -name "${service}*" 2>/dev/null)
    fi
  done

  if [ ${#instances[@]} -eq 0 ]; then
    echo "找不到任何 '$service' 的已安裝實例。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  while true; do
    clear
    echo "=================================="
    echo "請選擇要操作的 '$service' 實例："
    echo "----------------------------------"
    local i=1
    for instance in "${instances[@]}"; do
      echo "$i. $instance [${instance_modes[$((i - 1))]}]"
      i=$((i + 1))
    done
    echo "----------------------------------"
    echo "0. 取消"
    echo "=================================="
    if ! ui_prompt_index choice "請輸入選擇 [0-${#instances[@]}]: " 1 "${#instances[@]}" "" 0; then
      echo "操作已取消。"
      return 1
    fi

    # shellcheck disable=SC2034 # 供其他模組使用（apps_manage.sh）
    SELECTED_INSTANCE=${instances[$((choice - 1))]}
    # shellcheck disable=SC2034 # 供其他模組使用（apps_manage.sh）
    SELECTED_INSTANCE_MODE=${instance_modes[$((choice - 1))]}
    return 0
  done
}

_apps_default_mount_options() {
  local propagation="none"
  local selinux_flag
  selinux_flag="$(_apps_default_selinux_flag 1)"

  printf '%s %s\n' "$propagation" "$selinux_flag"
}

_apps_default_selinux_flag() {
  local warn="${1:-0}"

  if _is_selinux_enforcing; then
    if [ "$warn" = "1" ]; then
      echo "偵測到 SELinux Enforcing，將預設為 Volume 掛載添加 :Z 標籤（獨占；podman.sock 與部分 volume_dir 掛載會略過）。如需共享或停用可於自訂 Quadlet 時修改。" >&2
    fi
    echo "Z"
  else
    echo "none"
  fi
}
