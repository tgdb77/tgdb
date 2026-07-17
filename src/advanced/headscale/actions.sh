_headscale_create_ui_apikey_action() {
  local no_pause="${1:-0}"

  _headscale_require_tty || return $?
  _headscale_require_podman_for_quadlet || { ui_pause "按任意鍵返回..."; return 1; }

  load_system_config || true

  if podman container exists --help >/dev/null 2>&1; then
    if ! podman container exists "$HEADSCALE_CONTAINER_NAME" 2>/dev/null; then
      tgdb_warn "尚未部署 Headscale（找不到容器：$HEADSCALE_CONTAINER_NAME）。請先執行部署。"
      if [ "$no_pause" -ne 1 ]; then
        ui_pause "按任意鍵返回..."
      fi
      return 1
    fi
  else
    if ! podman ps -a --format '{{.Names}}' 2>/dev/null | grep -Fx -- "$HEADSCALE_CONTAINER_NAME" >/dev/null 2>&1; then
      tgdb_warn "尚未部署 Headscale（找不到容器：$HEADSCALE_CONTAINER_NAME）。請先執行部署。"
      if [ "$no_pause" -ne 1 ]; then
        ui_pause "按任意鍵返回..."
      fi
      return 1
    fi
  fi

  local out rc
  out="$(podman exec "$HEADSCALE_CONTAINER_NAME" headscale apikeys create --expiration 9999d 2>&1)" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "${out:-}" ]; then
    tgdb_fail "產生 API Key 失敗：${out:-（無輸出）}" 1 || true
  else
    printf '%s\n' "$out"
    tgdb_warn "請填入key至ui"
  fi

  if [ "$no_pause" -ne 1 ]; then
    ui_pause "按任意鍵返回..."
  fi
  return 0
}

headscale_p_install_tailscale_client() {
  _headscale_require_tty || return $?
  _headscale_load_tailscale_module || { ui_pause "按任意鍵返回..."; return 1; }
  tailscale_p_install_client || true
  return 0
}

headscale_p_join_headscale_server() {
  _headscale_require_tty || return $?
  _headscale_load_tailscale_module || { ui_pause "按任意鍵返回..."; return 1; }
  tailscale_p_join_headscale_server || true
  return 0
}

headscale_p_tailnet_port_forward() {
  _headscale_require_tty || return $?
  _headscale_load_tailscale_module || { ui_pause "按任意鍵返回..."; return 1; }
  tailscale_p_tailnet_port_forward || true
  return 0
}

_headscale_detect_root_domain_from_config() {
  local f
  f="$(_headscale_config_path)"
  [ -f "$f" ] || return 1

  local url host
  url="$(awk -F'"' '
    /^[[:space:]]*server_url:[[:space:]]*"/ { print $2; exit }
  ' "$f" 2>/dev/null || true)"
  [ -n "${url:-}" ] || return 1

  url="${url#http://}"
  url="${url#https://}"
  host="${url%%/*}"
  case "$host" in
    hs.*) printf '%s\n' "${host#hs.}"; return 0 ;;
  esac
  return 1
}

_headscale_nginx_site_conf_path() {
  local root_domain="$1"
  printf '%s\n' "$TGDB_DIR/nginx/configs/hs.${root_domain}.conf"
}

_headscale_render_nginx_site_conf() {
  local root_domain="$1"
  local host_port="${2:-$HEADSCALE_DEFAULT_HOST_PORT}"
  [ -n "$root_domain" ] || { tgdb_fail "root_domain 不可為空" 2 || return $?; }
  [ -n "$host_port" ] || host_port="$HEADSCALE_DEFAULT_HOST_PORT"

  local tpl
  tpl="$CONFIG_DIR/headscale/configs/hs.api.nginx.conf.example"
  if [ ! -f "$tpl" ]; then
    tgdb_fail "找不到 Nginx 站點範本：$tpl" 1 || return $?
  fi

  local out
  out="$(_headscale_nginx_site_conf_path "$root_domain")"
  mkdir -p "$(dirname "$out")"
  sed \
    -e "s/<root_domain>/$(_esc "$root_domain")/g" \
    -e "s/<host_port>/$(_esc "$host_port")/g" \
    "$tpl" >"$out"
  sed -i 's/\r$//' "$out" 2>/dev/null || true
  printf '%s\n' "$out"
  return 0
}

_headscale_setup_nginx_site_auto() {
  local root_domain="$1"
  local no_pause=0
  local host_port="${HEADSCALE_DEFAULT_HOST_PORT}"
  local ui_host_port="${HEADSCALE_DEFAULT_UI_HOST_PORT}"

  # 相容舊參數：
  # - _headscale_setup_nginx_site_auto <root_domain> <no_pause>
  # - _headscale_setup_nginx_site_auto <root_domain> <no_pause> <host_port>
  if [ "$#" -ge 2 ]; then
    no_pause="${2:-0}"
  fi
  if [ "$#" -ge 3 ] && [ -n "${3:-}" ]; then
    host_port="$3"
  else
    local existing_ports=""
    existing_ports="$(_headscale_read_ports_from_installed_pod_unit 2>/dev/null || true)"
    if [ -n "${existing_ports:-}" ]; then
      host_port="${existing_ports%,*}"
      ui_host_port="${existing_ports#*,}"
    fi
  fi

  if [ -z "${root_domain:-}" ]; then
    root_domain="$(_headscale_detect_root_domain_from_config 2>/dev/null || true)"
  fi
  if [ -z "${root_domain:-}" ]; then
    tgdb_warn "無法取得 root_domain，已略過 Nginx 反向代理站點自動設定。"
    return 1
  fi

  local fqdn
  fqdn="hs.${root_domain}"

  # 載入 nginx 模組（重用專案既有的憑證申請/重載流程）
  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "nginx-p" || return 1
  else
    # shellcheck source=src/advanced/nginx-p.sh
    source "$SCRIPT_DIR/nginx-p.sh"
  fi

  # 若 nginx 尚未部署，先部署（避免站點無法生效）
  if ! podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "nginx"; then
    tgdb_warn "尚未偵測到 Nginx 容器，將先嘗試部署 Nginx..."
    TGDB_CLI_MODE=1 nginx_p_deploy || true
  fi

  local cert_dir crt key
  cert_dir="$TGDB_DIR/nginx/certs"
  crt="$cert_dir/${fqdn}.crt"
  key="$cert_dir/${fqdn}.key"

  if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
    tgdb_warn "開始申請 ${fqdn} 憑證（會暫停 nginx 以釋放 80/TCP；需 DNS 指向與 80/TCP 對外可達）..."
    if ! _issue_cert_for_domain_p "$fqdn"; then
      tgdb_warn "申請憑證失敗，將改用 default.crt/default.key 讓站點仍可使用（瀏覽器會提示不受信任）。"
    fi
  fi

  local conf_path
  conf_path="$(_headscale_render_nginx_site_conf "$root_domain" "$host_port")" || return 1

  # 若憑證仍不存在，改用 default.crt/default.key 避免 nginx -t 失敗
  if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
    sed -i \
      -e "s|/etc/nginx/certs/${fqdn}\\.crt|/etc/nginx/certs/default.crt|g" \
      -e "s|/etc/nginx/certs/${fqdn}\\.key|/etc/nginx/certs/default.key|g" \
      "$conf_path" 2>/dev/null || true
  fi

  if declare -F _nginx_test_and_reload_podman >/dev/null 2>&1; then
    _nginx_test_and_reload_podman || true
  else
    _systemctl_user_try restart --no-block -- nginx.container nginx.service container-nginx.service || true
  fi

  tgdb_info "Nginx 站點已套用：$conf_path"
  tgdb_info "Headscale API：https://${fqdn}"
  tgdb_info "不公開 UI；請用 SSH 轉發127.0.0.1:${ui_host_port}/admin 訪問"
  if [ "$no_pause" -ne 1 ]; then
    ui_pause "按任意鍵返回..."
  fi
  return 0
}
