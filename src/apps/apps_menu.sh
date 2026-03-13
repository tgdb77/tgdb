#!/bin/bash

# Apps：互動選單（由 src/apps-p.sh 載入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_apps_load_nginx_shortcut_module() {
  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "nginx-p" || return 1
  else
    # shellcheck source=src/advanced/nginx-p.sh
    source "$SCRIPT_DIR/advanced/nginx-p.sh"
  fi
}

_apps_nginx_container_running() {
  podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "nginx"
}

_apps_ensure_nginx_ready_for_shortcut() {
  _apps_load_nginx_shortcut_module || return 1

  if _apps_nginx_container_running; then
    return 0
  fi

  tgdb_warn "尚未偵測到執行中的 Nginx，將先自動部署 Nginx。"
  nginx_p_deploy || true

  if _apps_nginx_container_running; then
    return 0
  fi

  tgdb_fail "Nginx 仍未啟動，請先到「進階應用 -> Nginx 管理」查看日誌後再試。" 1 || return $?
}

_apps_shortcut_add_reverse_proxy_site() {
  if ! _apps_ensure_nginx_ready_for_shortcut; then
    ui_pause "按任意鍵返回..."
    return 1
  fi
  nginx_p_add_reverse_proxy_site || true
}

_apps_shortcut_delete_reverse_proxy_site() {
  if ! _apps_ensure_nginx_ready_for_shortcut; then
    ui_pause "按任意鍵返回..."
    return 1
  fi
  nginx_p_delete_site || true
}

_service_menu() {
  local service="$1" display_name="$2" image="$3"
  local doc_url
  doc_url="$(_apps_service_doc_url "$service")"
  while true; do
    clear
    echo "=================================="
    echo "❖ $display_name 管理（Quadlet）❖"
    echo "=================================="
    if [ -n "$doc_url" ]; then
      echo "教學與文件：$doc_url"
    fi

    local ids=""
    ids="$(_apps_list_instances_by_label "$service" | head -n 1 2>/dev/null || true)"
    if [ -n "$ids" ]; then
      echo "已部署實例："
      _apps_print_instances_by_label "$service"
    fi
    echo "----------------------------------"
    echo "1. 快速部署"
    echo "2. 從紀錄部署"
    echo "3. 編輯紀錄"
    echo "4. 刪除紀錄"
    echo "5. 更新版本"
    echo "6. 完全移除"
    echo "7. podman管理傳送門"
    echo "8. 新增反向代理"
    echo "9. 刪除反向代理站點"
    echo "----------------------------------"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-9]: " c
    case "$c" in
      1)
        _deploy_app_quick "$service"
        local rc=$?
        if [ "$rc" -ne 0 ]; then
          if declare -F tgdb_print_last_error >/dev/null 2>&1; then
            tgdb_print_last_error || true
          fi
          ui_pause "按任意鍵返回..."
        fi
        ;;
      2)
        config_p_deployment_flow "$service" || true
        ;;
      3)
        edit_record_p "$service" || true
        ;;
      4)
        delete_record_p "$service" || true
        ;;
      5)
        _service_update_and_restart "$service" "$image"
        ;;
      6)
        _full_remove_instance "$service" "$image"
        ;;
      7)
        # shellcheck source=src/podman.sh
        source "$SCRIPT_DIR/podman.sh"
        podman_menu
        ;;
      8)
        _apps_shortcut_add_reverse_proxy_site
        ;;
      9)
        _apps_shortcut_delete_reverse_proxy_site
        ;;
      0) return ;;
      *) echo "無效選項"; sleep 1 ;;
    esac
  done
}

# ---- Apps-P 主選單 ----
apps_p_menu() {
  if ! _ensure_podman_version_for_quadlet; then
    return
  fi

  local -a services=()
  local s
  while IFS= read -r s; do
    [ -n "$s" ] && services+=("$s")
  done < <(_apps_list_services)

  while true; do
    clear
    echo "=================================="
    echo "❖ 應用程式管理（Quadlet）❖"
    echo "=================================="
    if [ ${#services[@]} -eq 0 ]; then
      tgdb_err "目前找不到任何可用的 app 規格（config/*/app.spec）。"
    else
      _apps_render_menu 3 1 "${services[@]}"
    fi
    echo "----------------------------------"
    echo "00. 自訂義程式管理（config/quadlet）"
    echo "----------------------------------"
    echo "0. 返回主選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-${#services[@]},00]: " c

    if [ "$c" = "00" ]; then
      config_quadlet_custom_menu
      continue
    fi
    if [ "$c" = "0" ]; then
      return
    fi
    if [[ ! "$c" =~ ^[0-9]+$ ]]; then
      echo "無效選項"
      sleep 1
      continue
    fi

    local idx=$((10#$c))
    if [ "$idx" -lt 1 ] || [ "$idx" -gt ${#services[@]} ]; then
      echo "無效選項"
      sleep 1
      continue
    fi

    local service="${services[$((idx - 1))]}"
    local display_name image
    display_name="$(_apps_service_display_name "$service")"
    image="$(_apps_service_default_image "$service")"
    _service_menu "$service" "$display_name" "$image"
  done
}
