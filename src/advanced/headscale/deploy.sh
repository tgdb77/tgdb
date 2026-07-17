headscale_p_deploy() {
  _headscale_require_tty || return $?
  _headscale_require_podman_for_quadlet || { ui_pause "按任意鍵返回..."; return 1; }

  load_system_config || true
  create_tgdb_dir || { ui_pause "按任意鍵返回..."; return 1; }

  _headscale_prepare_instance_configs

  local instance_dir
  instance_dir="$(_headscale_instance_dir)"

  local existing_ports=""
  existing_ports="$(_headscale_read_ports_from_installed_pod_unit 2>/dev/null || true)"

  local host_port="$HEADSCALE_DEFAULT_HOST_PORT"
  local ui_host_port="$HEADSCALE_DEFAULT_UI_HOST_PORT"
  if [ -n "${existing_ports:-}" ]; then
    host_port="${existing_ports%,*}"
    ui_host_port="${existing_ports#*,}"
  fi

  # 由使用者在部署流程中決定 API/UI 綁定埠（預設 18080/18081）
  local status
  if ! host_port="$(prompt_available_port "Headscale API 對外埠（127.0.0.1）" "$host_port")"; then
    status=$?
    if [ "$status" -eq 2 ]; then
      echo "已取消。"
      ui_pause "按任意鍵返回..."
      return 0
    fi
    tgdb_err "取得 API 埠失敗"
    ui_pause "按任意鍵返回..."
    return 1
  fi
  if ! ui_host_port="$(prompt_available_port "Headplane UI 對外埠（127.0.0.1）" "$ui_host_port")"; then
    status=$?
    if [ "$status" -eq 2 ]; then
      echo "已取消。"
      ui_pause "按任意鍵返回..."
      return 0
    fi
    tgdb_err "取得 UI 埠失敗"
    ui_pause "按任意鍵返回..."
    return 1
  fi
  if [ "$ui_host_port" = "$host_port" ]; then
    tgdb_err "API 與 UI 埠不可相同。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local env_path config_path
  env_path="$(_headscale_env_path)"
  config_path="$(_headscale_config_path)"

  # 防呆：若曾遇到 root_domain 未注入（例如 server_url 變成 https://hs.），提示重新產生設定檔。
  if [ -f "$config_path" ]; then
    if grep -qE '^[[:space:]]*server_url:[[:space:]]*"(https?|wss?)://hs\."$' "$config_path" 2>/dev/null || \
       grep -qE '^[[:space:]]*base_domain:[[:space:]]*"dns\."$' "$config_path" 2>/dev/null; then
      tgdb_warn "偵測到 config.yaml 可能缺少 root_domain 注入（server_url 或 dns.base_domain 以 '.' 結尾）。"
      if ui_confirm_yn "要立即重新產生 config.yaml 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        rm -f "$config_path" 2>/dev/null || true
      else
        [ "$?" -eq 2 ] && return 0
      fi
    fi
  fi

  # 不詢問：若檔案存在就沿用，避免覆蓋使用者修改。

  local root_domain="" db_user="" db_password=""
  local public_ipv4="" public_ipv6=""

  # 盡量從既有檔案抽取，以避免 .env 與 config.yaml 帳密不一致
  if [ -f "$env_path" ] && [ ! -f "$config_path" ]; then
    db_user="$(_headscale_env_get "$env_path" "POSTGRES_USER" || true)"
    db_password="$(_headscale_env_get "$env_path" "POSTGRES_PASSWORD" || true)"
    if [ -z "${db_user:-}" ] || [ -z "${db_password:-}" ]; then
      tgdb_warn "已存在 .env 但無法解析 POSTGRES_USER/POSTGRES_PASSWORD，將改用互動輸入。"
      db_user=""
      db_password=""
    fi
  elif [ -f "$config_path" ] && [ ! -f "$env_path" ]; then
    local creds
    creds="$(_headscale_config_get_pg_creds "$config_path" || true)"
    if [ -n "${creds:-}" ]; then
      db_user="${creds%,*}"
      db_password="${creds#*,}"
    else
      tgdb_warn "已存在 config.yaml 但無法解析資料庫帳密（postgres.user/pass），將改用互動輸入。"
    fi
  fi

  # 只有在需要生成檔案時，才詢問必要參數
  if [ ! -f "$env_path" ] || [ ! -f "$config_path" ]; then
    if [ ! -f "$config_path" ]; then
      _headscale_prompt_root_domain root_domain || { [ "$?" -eq 2 ] && return 0; return 1; }
    fi
    if [ -z "${db_user:-}" ]; then
      _headscale_prompt_pg_user db_user "headscale" || { [ "$?" -eq 2 ] && return 0; return 1; }
    fi
    if [ -z "${db_password:-}" ]; then
      _headscale_prompt_pg_password db_password || { [ "$?" -eq 2 ] && return 0; return 1; }
    fi
  fi

  if [ ! -f "$env_path" ]; then
    _headscale_write_env "$db_user" "$db_password" || { ui_pause "按任意鍵返回..."; return 1; }
    echo "✅ 已生成：$env_path"
  else
    echo "已沿用：$env_path"
  fi

  if [ ! -f "$config_path" ]; then
    public_ipv4="$(_headscale_detect_public_ipv4 2>/dev/null || true)"
    public_ipv6="$(_headscale_detect_public_ipv6 2>/dev/null || true)"

    if _headscale_is_ipv4_addr "$public_ipv4"; then
      echo "ℹ️ 初次生成 config.yaml：已偵測公網 IPv4：$public_ipv4"
    else
      tgdb_warn "初次生成 config.yaml：未能自動偵測公網 IPv4，將保留範本預設值。"
      public_ipv4=""
    fi
    if _headscale_is_ipv6_addr "$public_ipv6"; then
      echo "ℹ️ 初次生成 config.yaml：已偵測公網 IPv6：$public_ipv6"
    else
      tgdb_warn "初次生成 config.yaml：未能自動偵測公網 IPv6，將保留範本預設值。"
      public_ipv6=""
    fi

    _headscale_render_config_yaml "$root_domain" "$db_user" "$db_password" "$public_ipv4" "$public_ipv6" || { ui_pause "按任意鍵返回..."; return 1; }
    echo "✅ 已生成：$config_path"
  else
    echo "已沿用：$config_path"
  fi

  # Headplane 要能在 UI 編輯 ACL，建議使用 policy.mode=database（避免 file 模式顯示唯讀）。
  _headscale_ensure_acl_policy_database_mode || true

  echo "----------------------------------"
  echo "即將套用 Headscale（固定容器名：$HEADSCALE_CONTAINER_NAME）"
  echo "目錄：$instance_dir"
  echo "PublishPort：127.0.0.1:${host_port} -> 8080（Headscale）"
  echo "PublishPort：127.0.0.1:${ui_host_port} -> 8081（Headplane）"
  echo "----------------------------------"

  # 安全優先：預設只在本機回環提供 Headplane（用 SSH 轉發訪問）
  _headscale_render_headplane_config_yaml "$root_domain" "$ui_host_port" || true

  # Headplane（Integrated Mode）會用 Podman API socket（docker.sock 介面），先確保已啟用 podman.socket
  if command -v systemctl >/dev/null 2>&1; then
    if ! _systemctl_user_try is-active -- podman.socket >/dev/null 2>&1; then
      echo "正在為目前使用者啟用 Podman Socket（podman.sock）..."
      if ! _systemctl_user_try enable --now -- podman.socket >/dev/null 2>&1; then
        tgdb_warn "無法啟用 Podman Socket，Headplane 的整合功能可能無法運作。"
      fi
    fi
  else
    tgdb_warn "系統未提供 systemctl，無法自動啟用 Podman Socket。"
  fi

  _headscale_install_quadlet_units "$host_port" "$ui_host_port" || { ui_pause "按任意鍵返回..."; return 1; }

  # 切換到 Headplane 後，清理舊的 headscale-ui（若存在）
  _systemctl_user_try disable --now -- \
    "${HEADSCALE_CONTAINER_NAME}-ui.container" \
    "container-${HEADSCALE_CONTAINER_NAME}-ui.service" \
    "${HEADSCALE_CONTAINER_NAME}-ui.service" 2>/dev/null || true
  local old_ui_unit
  old_ui_unit="$(_headscale_resolved_unit_path "${HEADSCALE_CONTAINER_NAME}-ui.container" 2>/dev/null || true)"
  if [ -n "${old_ui_unit:-}" ] && [ -f "$old_ui_unit" ]; then
    rm -f "$old_ui_unit" 2>/dev/null || true
    _systemctl_user_try daemon-reload || true
  fi
  local old_ui_legacy=""
  old_ui_legacy="$(rm_legacy_quadlet_unit_path_by_mode "${HEADSCALE_CONTAINER_NAME}-ui.container" rootless 2>/dev/null || true)"
  if [ -n "${old_ui_legacy:-}" ] && [ "$old_ui_legacy" != "$old_ui_unit" ] && [ -f "$old_ui_legacy" ]; then
    rm -f "$old_ui_legacy" 2>/dev/null || true
    _systemctl_user_try daemon-reload || true
  fi
  podman rm -f "${HEADSCALE_CONTAINER_NAME}-ui" 2>/dev/null || true

  echo "✅ Headscale 啟動中"
  echo "  - Headscale:    http://127.0.0.1:${host_port}"
  echo "  - Headplane:    http://127.0.0.1:${ui_host_port}/admin"
  echo "----------------------------------"
  echo "本地訪問建議（用 SSH 轉發）："
  echo "  ssh -L ${ui_host_port}:127.0.0.1:${ui_host_port} <server>"
  echo "  然後開啟：http://127.0.0.1:${ui_host_port}/admin"
  echo "----------------------------------"

  # 反代到網域（只對外提供 Headscale API；不公開 Headplane）
  # 注意：Headplane 預設只綁本機回環，請用 SSH 轉發訪問。
  _headscale_setup_nginx_site_auto "${root_domain:-}" 1 "$host_port" || true
  ui_pause "按任意鍵返回..."
  return 0
}

_headscale_detect_root_domain_from_nginx_site() {
  local conf_dir="$TGDB_DIR/nginx/configs"
  [ -d "$conf_dir" ] || return 1

  local -a files=()
  local f
  for f in "$conf_dir"/hs.*.conf; do
    [ -f "$f" ] && files+=("$f")
  done

  if [ ${#files[@]} -ne 1 ]; then
    return 1
  fi

  local base fqdn
  base="$(basename "${files[0]}")"
  fqdn="${base%.conf}"
  case "$fqdn" in
    hs.*) printf '%s\n' "${fqdn#hs.}"; return 0 ;;
  esac
  return 1
}

_headscale_remove_nginx_site_auto() {
  local root_domain="$1"

  # 嘗試從 headscale config 推導；若失敗再從 nginx configs 回推（僅當唯一 hs.*.conf）
  if [ -z "${root_domain:-}" ]; then
    root_domain="$(_headscale_detect_root_domain_from_config 2>/dev/null || true)"
  fi
  if [ -z "${root_domain:-}" ]; then
    root_domain="$(_headscale_detect_root_domain_from_nginx_site 2>/dev/null || true)"
  fi
  [ -n "${root_domain:-}" ] || return 0

  local fqdn
  fqdn="hs.${root_domain}"

  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "nginx-p" || return 1
  else
    # shellcheck source=src/advanced/nginx-p.sh
    source "$SCRIPT_DIR/nginx-p.sh"
  fi

  # nginx_p_delete_site_cli 會自行處理：站點 conf/快取/（可判定的）憑證/續簽資料
  nginx_p_delete_site_cli "$fqdn" || true
  return 0
}

_headscale_remove_menu() {
  _headscale_require_tty || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ 移除應用 ❖"
    echo "=================================="
    echo "1. 移除 Headscale（含 Postgres / Headplane / Nginx 站點）"
    echo "2. 移除 DERP（derper）"
    echo "----------------------------------"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-2]: " choice

    case "$choice" in
      1) headscale_p_full_remove || true ;;
      2)
        _headscale_load_derper_module || { ui_pause "按任意鍵返回..."; continue; }
        derper_p_full_remove || true
        ;;
      0) return 0 ;;
      *) echo "無效選項，請重新輸入。"; sleep 1 ;;
    esac
  done
}

headscale_p_full_remove() {
  _headscale_require_tty || return $?

  load_system_config || true
  local instance_dir
  instance_dir="$(_headscale_instance_dir)"

  local root_domain=""
  root_domain="$(_headscale_detect_root_domain_from_config 2>/dev/null || true)"

  echo "=================================="
  echo "❖ Headscale：移除應用 ❖"
  echo "=================================="
  echo "此操作會："
  echo "1) 停止/停用 systemd user 單元（pod/container）"
  echo "2) 移除 Quadlet 單元檔"
  echo "3) 嘗試刪除 Podman pod/container"
  echo "4) （可選）刪除持久化目錄：$instance_dir"
  echo "----------------------------------"

  local deld_rc=0
  if ! ui_confirm_yn "要刪除持久化目錄嗎？（$instance_dir）(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    deld_rc=$?
    if [ "$deld_rc" -eq 2 ]; then
      echo "操作已取消"
      ui_pause "按任意鍵返回..."
      return 0
    fi
  fi

  _systemctl_user_try stop --no-block -- \
    "${HEADSCALE_CONTAINER_NAME}.pod" "pod-${HEADSCALE_CONTAINER_NAME}.service" \
    "${HEADSCALE_CONTAINER_NAME}.container" "${HEADSCALE_CONTAINER_NAME}.service" "container-${HEADSCALE_CONTAINER_NAME}.service" \
    "${HEADSCALE_CONTAINER_NAME}-postgres.container" "container-${HEADSCALE_CONTAINER_NAME}-postgres.service" \
    "${HEADSCALE_CONTAINER_NAME}-headplane.container" "container-${HEADSCALE_CONTAINER_NAME}-headplane.service" \
    "${HEADSCALE_CONTAINER_NAME}-ui.container" "container-${HEADSCALE_CONTAINER_NAME}-ui.service" || true

  _systemctl_user_try disable -- \
    "${HEADSCALE_CONTAINER_NAME}.pod" \
    "${HEADSCALE_CONTAINER_NAME}.container" \
    "${HEADSCALE_CONTAINER_NAME}-postgres.container" \
    "${HEADSCALE_CONTAINER_NAME}-headplane.container" \
    "${HEADSCALE_CONTAINER_NAME}-ui.container" || true

  # 一條龍：移除 nginx 站點（若曾部署 hs.<root_domain> 反向代理）
  _headscale_remove_nginx_site_auto "$root_domain" || true

  podman pod rm -f "$HEADSCALE_CONTAINER_NAME" 2>/dev/null || true
  podman rm -f \
    "$HEADSCALE_CONTAINER_NAME" \
    "${HEADSCALE_CONTAINER_NAME}-postgres" \
    "${HEADSCALE_CONTAINER_NAME}-headplane" \
    "${HEADSCALE_CONTAINER_NAME}-ui" 2>/dev/null || true

  local unit
  for unit in \
    "${HEADSCALE_CONTAINER_NAME}.pod" \
    "${HEADSCALE_CONTAINER_NAME}.container" \
    "${HEADSCALE_CONTAINER_NAME}-postgres.container" \
    "${HEADSCALE_CONTAINER_NAME}-headplane.container" \
    "${HEADSCALE_CONTAINER_NAME}-ui.container"; do
    local p
    p="$(_headscale_resolved_unit_path "$unit" 2>/dev/null || true)"
    if [ -n "${p:-}" ] && [ -f "$p" ]; then
      rm -f "$p" 2>/dev/null || true
    fi
    local legacy_p=""
    legacy_p="$(rm_legacy_quadlet_unit_path_by_mode "$unit" rootless 2>/dev/null || true)"
    if [ -n "${legacy_p:-}" ] && [ "$legacy_p" != "$p" ] && [ -f "$legacy_p" ]; then
      rm -f "$legacy_p" 2>/dev/null || true
    fi
  done

  _systemctl_user_try daemon-reload || true

  if [ "$deld_rc" -eq 0 ]; then
    # 對齊 Apps 體驗：用 podman unshare rm -rf 刪除，避免 rootless 權限造成刪不乾淨
    local rp_dir rp_base
    rp_dir="$(readlink -f "$instance_dir" 2>/dev/null || echo "$instance_dir")"
    rp_base="$(_headscale_instance_dir)"
    rp_base="$(readlink -f "$rp_base" 2>/dev/null || printf '%s\n' "$rp_base")"
    if [ "$rp_dir" != "$rp_base" ]; then
      tgdb_warn "安全保護：拒絕刪除非預期路徑：$instance_dir"
    else
      if command -v podman >/dev/null 2>&1; then
        if ! podman unshare rm -rf -- "$rp_dir" 2>/dev/null; then
          if [ -d "$rp_dir" ]; then
            tgdb_warn "無法刪除資料夾：$rp_dir"
            tgdb_warn "可能因權限不足（例如容器以 root 建立檔案），請使用 sudo 或 root 手動清理。"
          fi
        fi
      else
        rm -rf -- "$rp_dir" 2>/dev/null || true
      fi
    fi
    echo "✅ 已移除並刪除持久化目錄：$instance_dir"
  else
    echo "✅ 已移除單元，已保留持久化目錄：$instance_dir"
  fi

  ui_pause "按任意鍵返回..."
  return 0
}
