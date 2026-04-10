#!/bin/bash

# Headscale（含 Postgres + Headplane / Podman + Quadlet）管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

HEADSCALE_CONTAINER_NAME="headscale"
HEADSCALE_DEFAULT_HOST_PORT="18080"
HEADSCALE_DEFAULT_UI_HOST_PORT="18081"

_headscale_resolved_unit_path() {
  local unit="$1"
  _quadlet_runtime_or_legacy_unit_path "$unit" "headscale"
}

_headscale_load_tailscale_module() {
  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "tailscale-p" || return 1
    return 0
  fi

  local p="$SCRIPT_DIR/tailscale-p.sh"
  if [ ! -f "$p" ]; then
    tgdb_fail "找不到 tailscale 模組：$p" 1 || true
    return 1
  fi

  # shellcheck source=src/advanced/tailscale-p.sh
  source "$p"
  return 0
}

_headscale_require_tty() {
  if ! ui_is_interactive; then
    tgdb_fail "Headscale 佈署需要互動式終端（TTY）。" 2 || return $?
    return 2
  fi
  return 0
}

_headscale_require_podman_for_quadlet() {
  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 Podman，Headscale 佈署需要使用 Podman + Quadlet。" 1 || true
    echo "請先到主選單：5. Podman 管理 → 安裝/更新 Podman"
    return 1
  fi

  local ver_str major minor
  ver_str="$(podman --version 2>/dev/null | awk '{print $3}' || true)"
  ver_str="${ver_str%%-*}"
  IFS='.' read -r major minor _ <<< "${ver_str:-}"
  if [[ ! "${major:-}" =~ ^[0-9]+$ ]] || [[ ! "${minor:-}" =~ ^[0-9]+$ ]]; then
    tgdb_warn "無法解析 Podman 版本字串：$(podman --version 2>/dev/null || true)"
    return 0
  fi
  if [ "$major" -lt 4 ] || { [ "$major" -eq 4 ] && [ "$minor" -lt 4 ]; }; then
    tgdb_warn "偵測到 Podman v${major}.${minor}，Quadlet 建議使用 Podman 4.4+（否則可能無法正常啟動）。"
  fi
  return 0
}

_headscale_instance_dir() { printf '%s\n' "$TGDB_DIR/headscale"; }
_headscale_repo_quadlet_dir() { printf '%s\n' "$CONFIG_DIR/headscale/quadlet"; }
_headscale_repo_configs_dir() { printf '%s\n' "$CONFIG_DIR/headscale/configs"; }

_headscale_env_path() { printf '%s\n' "$(_headscale_instance_dir)/.env"; }
_headscale_config_path() { printf '%s\n' "$(_headscale_instance_dir)/etc/config.yaml"; }
_headscale_derpmap_path() { printf '%s\n' "$(_headscale_instance_dir)/etc/derpmap.yaml"; }
_headscale_headplane_config_path() { printf '%s\n' "$(_headscale_instance_dir)/headplane/etc/config.yaml"; }

_headscale_ensure_layout() {
  local dir
  dir="$(_headscale_instance_dir)"
  mkdir -p "$dir/etc" "$dir/lib" "$dir/run" "$dir/pgdata" \
    "$dir/headplane/etc" "$dir/headplane/lib"
}

_headscale_is_valid_root_domain() {
  local d="${1:-}"
  [ -n "$d" ] || return 1
  case "$d" in
    *" "*|*"/"*|*"\\"*|*":"*|*"@"*|*"?"*|*"#"*) return 1 ;;
  esac
  [[ "$d" == *.* ]] || return 1
  [[ "$d" != .* ]] && [[ "$d" != *. ]]
}

_headscale_is_safe_pg_user() {
  local u="${1:-}"
  [ -n "$u" ] || return 1
  [[ "$u" =~ ^[a-zA-Z0-9_]+$ ]]
}

_headscale_prompt_root_domain() {
  local out_var="$1"
  local value=""
  while true; do
    read -r -e -p "請輸入 root_domain（例：example.com，輸入 0 取消）: " value
    if [ "$value" = "0" ]; then
      return 2
    fi
    if _headscale_is_valid_root_domain "$value"; then
      printf -v "$out_var" '%s' "$value"
      return 0
    fi
    tgdb_err "root_domain 格式不正確（例：example.com；不可包含空白、/、:、@）。"
  done
}

_headscale_prompt_pg_user() {
  local out_var="$1"
  local default_user="${2:-headscale}"
  local u=""
  while true; do
    read -r -e -p "請輸入資料庫帳號（Postgres USER，預設：${default_user}，輸入 0 取消）: " u
    if [ "$u" = "0" ]; then
      return 2
    fi
    u="${u:-$default_user}"
    if _headscale_is_safe_pg_user "$u"; then
      printf -v "$out_var" '%s' "$u"
      return 0
    fi
    tgdb_err "資料庫帳號僅允許英數與底線（例：headscale）。"
  done
}

_headscale_prompt_pg_password() {
  local out_var="$1"
  local p1="" p2=""
  while true; do
    read -r -s -p "請輸入資料庫密碼（不可為空，輸入 0 取消）: " p1
    echo
    if [ "$p1" = "0" ]; then
      return 2
    fi
    if [ -z "$p1" ]; then
      tgdb_err "密碼不可為空。"
      continue
    fi
    if printf '%s' "$p1" | grep -q '[[:space:]]' 2>/dev/null; then
      tgdb_err "密碼不可包含空白字元（避免 .env 解析問題）。"
      continue
    fi
    if printf '%s' "$p1" | grep -q '["\\]' 2>/dev/null; then
      tgdb_err "密碼不可包含雙引號或反斜線（避免 YAML/.env 轉義問題）。"
      continue
    fi
    read -r -s -p "請再次輸入密碼確認: " p2
    echo
    if [ "$p1" != "$p2" ]; then
      tgdb_err "兩次輸入的密碼不一致，請重試。"
      continue
    fi
    printf -v "$out_var" '%s' "$p1"
    return 0
  done
}

_headscale_read_ports_from_installed_pod_unit() {
  local pod_unit
  pod_unit="$(_headscale_resolved_unit_path "${HEADSCALE_CONTAINER_NAME}.pod" 2>/dev/null || true)"
  [ -f "$pod_unit" ] || return 1

  local hp="" uhp="" line
  while IFS= read -r line; do
    case "$line" in
      PublishPort=127.0.0.1:*:8080)
        hp="${line#PublishPort=127.0.0.1:}"
        hp="${hp%:8080}"
        ;;
      PublishPort=127.0.0.1:*:8081)
        uhp="${line#PublishPort=127.0.0.1:}"
        uhp="${uhp%:8081}"
        ;;
    esac
  done <"$pod_unit"

  if [[ "${hp:-}" =~ ^[0-9]+$ ]] && [[ "${uhp:-}" =~ ^[0-9]+$ ]]; then
    printf '%s,%s\n' "$hp" "$uhp"
    return 0
  fi
  return 1
}

_headscale_write_env() {
  local db_user="$1" db_password="$2"
  local env_path
  env_path="$(_headscale_env_path)"

  cat >"$env_path" <<EOF
# headscale Postgres 初始化（由 TGDB 生成）
#
# 注意：此檔案包含密碼，建議權限設為 600。

POSTGRES_DB=headscale
POSTGRES_USER=${db_user}
POSTGRES_PASSWORD=${db_password}
EOF

  chmod 600 "$env_path" 2>/dev/null || true
  return 0
}

_headscale_env_get() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  [ -n "$key" ] || return 1
  awk -F= -v k="$key" '
    $1==k {
      $1=""
      sub(/^=/, "", $0)
      print $0
      exit
    }
  ' "$file" 2>/dev/null
}

_headscale_ensure_acl_policy_database_mode() {
  local config_path
  config_path="$(_headscale_config_path)"

  [ -f "$config_path" ] || return 0

  # 依目前策略：一律使用 database 模式，讓 Headplane 可直接透過 API 編輯 ACL
  # （Headplane 在 file 模式通常會提示 Read-only ACL Policy）
  local tmp out changed
  tmp="$(mktemp 2>/dev/null || echo "$(_headscale_instance_dir)/etc/.config.yaml.tmp")"
  out="$tmp"
  changed=0

  awk '
    BEGIN {
      in_policy=0
      found_policy=0
      found_mode=0
      found_path=0
    }
    function print_policy_defaults_if_missing() {
      if (found_mode==0) {
        print "  mode: \"database\""
      }
      if (found_path==0) {
        print "  path: \"\""
      }
    }
    /^policy:[[:space:]]*$/ {
      found_policy=1
      in_policy=1
      found_mode=0
      found_path=0
      print
      next
    }
    in_policy==1 {
      # policy block 結束（下一個頂層 key）
      if ($0 ~ /^[^[:space:]]/ && $0 !~ /^#/) {
        print_policy_defaults_if_missing()
        in_policy=0
        print
        next
      }
      if ($0 ~ /^[[:space:]]*mode:[[:space:]]*/) {
        print "  mode: \"database\""
        found_mode=1
        next
      }
      if ($0 ~ /^[[:space:]]*path:[[:space:]]*/) {
        print "  path: \"\""
        found_path=1
        next
      }
    }
    { print }
    END {
      if (in_policy==1) {
        print_policy_defaults_if_missing()
      }
      if (found_policy==0) {
        print ""
        print "# ACL（由 TGDB 自動啟用，供 Headplane 編輯）"
        print "policy:"
        print "  mode: \"database\""
        print "  path: \"\""
      }
    }
  ' "$config_path" >"$out" 2>/dev/null || true

  if [ -f "$out" ] && ! cmp -s "$config_path" "$out" 2>/dev/null; then
    if mv -f "$out" "$config_path" 2>/dev/null; then
      changed=1
    else
      if cp -f "$out" "$config_path" 2>/dev/null; then
        changed=1
      fi
      rm -f "$out" 2>/dev/null || true
    fi
  fi
  rm -f "$tmp" 2>/dev/null || true

  if [ "$changed" -eq 1 ]; then
    echo "✅ 已啟用 ACL database 模式：policy.mode=database（供 Headplane 編輯）"
  fi
  return 0
}

_headscale_config_get_pg_creds() {
  local file="$1"
  [ -f "$file" ] || return 1

  awk '
    function strip_quotes(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/^"/, "", s)
      gsub(/"$/, "", s)
      return s
    }
    /^[[:space:]]*postgres:[[:space:]]*$/ {in_pg=1; next}
    in_pg && /^[[:space:]]*user:[[:space:]]*/ {
      sub(/^[[:space:]]*user:[[:space:]]*/, "", $0)
      user=strip_quotes($0)
      next
    }
    in_pg && /^[[:space:]]*pass:[[:space:]]*/ {
      sub(/^[[:space:]]*pass:[[:space:]]*/, "", $0)
      pass=strip_quotes($0)
      next
    }
    in_pg && /^[^[:space:]]/ {in_pg=0}
    END {
      if (user!="" && pass!="") print user "," pass
    }
  ' "$file" 2>/dev/null
}

_headscale_render_config_yaml() {
  local root_domain="$1" db_user="$2" db_password="$3"

  local tpl
  tpl="$(_headscale_repo_configs_dir)/config.yaml.example"
  if [ ! -f "$tpl" ]; then
    tgdb_fail "找不到 Headscale 設定樣板：$tpl" 1 || return $?
  fi

  local out
  out="$(_headscale_config_path)"

  local esc_root esc_pass esc_user
  esc_root="$(_esc "$root_domain")"
  esc_user="$(_esc "$db_user")"
  esc_pass="$(_esc "$db_password")"

  mkdir -p "$(dirname "$out")"
  sed \
    -e "s/<root_domain>/${esc_root}/g" \
    -e "s/<db_password>/${esc_pass}/g" \
    -e "s/^[[:space:]]*user:[[:space:]]*\"[^\"]*\"/    user: \"${esc_user}\"/g" \
    "$tpl" >"$out"

  chmod 600 "$out" 2>/dev/null || true
  return 0
}

_headscale_copy_example_if_missing() {
  local src="$1" dst="$2"
  [ -f "$dst" ] && return 0
  [ -f "$src" ] || return 0
  mkdir -p "$(dirname "$dst")"
  cp -n "$src" "$dst" 2>/dev/null || true
  return 0
}

_headscale_prepare_instance_configs() {
  _headscale_ensure_layout

  _headscale_copy_example_if_missing "$(_headscale_repo_configs_dir)/derpmap.yaml.example" "$(_headscale_derpmap_path)"
  # Headplane 設定：會在部署流程中依使用情境（本地/反代）補齊關鍵欄位
  _headscale_copy_example_if_missing "$(_headscale_repo_configs_dir)/headplane.config.yaml.example" "$(_headscale_headplane_config_path)"
  return 0
}

_headscale_generate_cookie_secret() {
  # Headplane 0.6.x 要求 server.cookie_secret 長度必須「剛好 32」。
  # 用 16 bytes hex（=32 字元）最穩。
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16 2>/dev/null | tr -d '\n' && echo ""
    return 0
  fi
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | head -c 32 && echo ""
    return 0
  fi
  # fallback：不理想但可用（只確保長度正確；建議有 openssl 時改用 openssl rand -hex 16）
  printf '%08x%08x%08x%08x\n' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
  return 0
}

_headscale_render_headplane_config_yaml() {
  local root_domain="$1"
  local ui_host_port="$2"

  local tpl out
  tpl="$(_headscale_repo_configs_dir)/headplane.config.yaml.example"
  out="$(_headscale_headplane_config_path)"

  if [ ! -f "$tpl" ]; then
    tgdb_fail "找不到 Headplane 設定範本：$tpl" 1 || return $?
  fi

  mkdir -p "$(dirname "$out")"

  local base_url cookie_secret
  # 安全優先：預設只綁本機回環，建議用 SSH 轉發訪問（不做 Nginx 公網反代）
  base_url="http://127.0.0.1:${ui_host_port}"
  cookie_secret=""

  # 若已存在且符合規格（長度 32），沿用避免每次部署都輪替
  if [ -f "$out" ]; then
    cookie_secret="$(sed -n 's/^[[:space:]]*cookie_secret:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' "$out" 2>/dev/null | head -n 1 || true)"
    if [ "${#cookie_secret}" -ne 32 ]; then
      cookie_secret=""
    fi
  fi
  if [ -z "${cookie_secret:-}" ]; then
    cookie_secret="$(_headscale_generate_cookie_secret)"
  fi

  local src tmp tmp2 need_host need_strict
  src="$tpl"
  [ -f "$out" ] && src="$out"

  tmp="$(mktemp 2>/dev/null || echo "$(_headscale_instance_dir)/headplane/etc/.config.yaml.tmp")"
  tmp2="$(mktemp 2>/dev/null || echo "$(_headscale_instance_dir)/headplane/etc/.config.yaml.tmp2")"

  sed \
    -e "s|<root_domain>|$(_esc "$root_domain")|g" \
    -e "s|^[[:space:]]*base_url:.*|  base_url: \"${base_url}\"|g" \
    -e "s|^[[:space:]]*cookie_secret:.*|  cookie_secret: \"${cookie_secret}\"|g" \
    -e "s|^[[:space:]]*cookie_secure:.*|  cookie_secure: false|g" \
    -e "s|^[[:space:]]*port:[[:space:]]*[0-9][0-9]*|  port: 8081|g" \
    "$src" >"$tmp"

  need_host=1
  if grep -q '^[[:space:]]*host:[[:space:]]*' "$tmp" 2>/dev/null; then
    need_host=0
  fi
  need_strict=1
  if grep -q '^[[:space:]]*config_strict:[[:space:]]*' "$tmp" 2>/dev/null; then
    need_strict=0
  fi

  awk -v need_host="$need_host" -v need_strict="$need_strict" '
    /^server:[[:space:]]*$/ {
      print
      if (need_host == 1) {
        print "  host: \"0.0.0.0\""
      }
      next
    }
    /^headscale:[[:space:]]*$/ {
      print
      if (need_strict == 1) {
        print "  config_strict: false"
      }
      next
    }
    { print }
  ' "$tmp" >"$tmp2"

  if ! mv -f "$tmp2" "$out" 2>/dev/null; then
    cp -f "$tmp2" "$out"
    rm -f "$tmp2" 2>/dev/null || true
  fi
  rm -f "$tmp" 2>/dev/null || true

  sed -i 's/\r$//' "$out" 2>/dev/null || true
  echo "✅ 已生成/更新：$out"
  return 0
}

_headscale_render_quadlet_units_to_dir() {
  local out_dir="$1"
  local host_port="$2"
  local ui_host_port="$3"

  [ -n "$out_dir" ] || { tgdb_fail "out_dir 不可為空" 2 || return $?; }
  mkdir -p "$out_dir"

  local instance_dir
  instance_dir="$(_headscale_instance_dir)"

  local tpl_dir
  tpl_dir="$(_headscale_repo_quadlet_dir)"
  if [ ! -d "$tpl_dir" ]; then
    tgdb_fail "找不到 Quadlet 樣板目錄：$tpl_dir" 1 || return $?
  fi

  local esc_inst esc_cn esc_hp esc_uip esc_uid
  esc_inst="$(_esc "$instance_dir")"
  esc_cn="$(_esc "$HEADSCALE_CONTAINER_NAME")"
  esc_hp="$(_esc "$host_port")"
  esc_uip="$(_esc "$ui_host_port")"
  esc_uid="$(_esc "$(id -u 2>/dev/null || echo "")")"

  sed \
    -e "s|\${instance_dir}|$esc_inst|g" \
    -e "s|\${container_name}|$esc_cn|g" \
    -e "s|\${host_port}|$esc_hp|g" \
    -e "s|\${ui_host_port}|$esc_uip|g" \
    "$tpl_dir/default.pod" >"$out_dir/${HEADSCALE_CONTAINER_NAME}.pod"

  sed \
    -e "s|\${instance_dir}|$esc_inst|g" \
    -e "s|\${container_name}|$esc_cn|g" \
    "$tpl_dir/default.container" >"$out_dir/${HEADSCALE_CONTAINER_NAME}.container"

  sed \
    -e "s|\${instance_dir}|$esc_inst|g" \
    -e "s|\${container_name}|$esc_cn|g" \
    "$tpl_dir/default2.container" >"$out_dir/${HEADSCALE_CONTAINER_NAME}-postgres.container"

  # Headplane（取代 headscale-ui）：使用 default3.container（避免額外檔名）
  if [ ! -f "$tpl_dir/default3.container" ]; then
    tgdb_fail "找不到 Headplane Quadlet 範本：$tpl_dir/default3.container" 1 || return $?
  fi
  sed \
    -e "s|\${instance_dir}|$esc_inst|g" \
    -e "s|\${container_name}|$esc_cn|g" \
    -e "s|\${user_id}|$esc_uid|g" \
    "$tpl_dir/default3.container" >"$out_dir/${HEADSCALE_CONTAINER_NAME}-headplane.container"

  return 0
}

_headscale_install_quadlet_units() {
  local host_port="$1"
  local ui_host_port="$2"

  local tmp_dir=""
  tmp_dir="$(mktemp -d 2>/dev/null || true)"
  if [ -z "${tmp_dir:-}" ]; then
    tgdb_fail "無法建立暫存目錄（mktemp -d）" 1 || return $?
  fi

  _headscale_render_quadlet_units_to_dir "$tmp_dir" "$host_port" "$ui_host_port" || {
    rm -rf "$tmp_dir" 2>/dev/null || true
    return 1
  }

  local -a units=(
    "$tmp_dir/${HEADSCALE_CONTAINER_NAME}.pod"
    "$tmp_dir/${HEADSCALE_CONTAINER_NAME}.container"
    "$tmp_dir/${HEADSCALE_CONTAINER_NAME}-postgres.container"
    "$tmp_dir/${HEADSCALE_CONTAINER_NAME}-headplane.container"
  )

  local rc=0
  _install_service_quadlet_units_from_files "headscale" "$HEADSCALE_CONTAINER_NAME" "${units[@]}" || rc=$?

  rm -rf "$tmp_dir" 2>/dev/null || true
  [ "$rc" -eq 0 ] || return "$rc"
  return 0
}

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
    _headscale_render_config_yaml "$root_domain" "$db_user" "$db_password" || { ui_pause "按任意鍵返回..."; return 1; }
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

headscale_p_full_remove() {
  _headscale_require_tty || return $?

  load_system_config || true
  local instance_dir
  instance_dir="$(_headscale_instance_dir)"

  local root_domain=""
  root_domain="$(_headscale_detect_root_domain_from_config 2>/dev/null || true)"

  echo "=================================="
  echo "❖ Headscale：完整移除 ❖"
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

  # 一條龍：若有安裝/加入 tailscale 客戶端，完整移除時可選同步退出並停用（必要時卸載）
  if _headscale_load_tailscale_module 2>/dev/null; then
    if ui_confirm_yn "偵測到 tailscale 客戶端（可能曾由 TGDB 安裝/加入）。要同步清理（down/logout、停用 tailscaled；若是 TGDB 安裝則嘗試卸載）嗎？(y/N，預設 Y，輸入 0 取消): " "Y"; then
      tailscale_p_cleanup_if_needed || true
    fi
  fi

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

  # 一條龍：可選同步移除 DERP（derper）
  if ui_confirm_yn "要同時移除 DERP（derper）嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    if declare -F tgdb_load_module >/dev/null 2>&1; then
      tgdb_load_module "derper-p" || { ui_pause "按任意鍵返回..."; return 0; }
    else
      # shellcheck source=src/advanced/derper-p.sh
      source "$SCRIPT_DIR/derper-p.sh"
    fi
    if declare -F derper_p_full_remove_integrated >/dev/null 2>&1; then
      derper_p_full_remove_integrated || true
    fi
  fi

  ui_pause "按任意鍵返回..."
  return 0
}

_headscale_podman_container_status_label() {
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

  echo "❌ 未執行"
  return 0
}

_headscale_system_unit_active_label() {
  local unit="$1"

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "未知（缺少 systemctl）"
    return 0
  fi

  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    echo "✅ 執行中"
    return 0
  fi

  if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    echo "⏸ 已安裝"
    return 0
  fi

  echo "❌ 未執行"
  return 0
}

_headscale_print_runtime_status() {
  load_system_config || true

  local hs_label tsd_label ts_label derp_label
  hs_label="$(_headscale_podman_container_status_label "$HEADSCALE_CONTAINER_NAME")"
  derp_label="$(_headscale_podman_container_status_label "derper")"
  tsd_label="$(_headscale_system_unit_active_label "tailscaled.service")"
  ts_label="未知"
  if declare -F tailscale_p_login_label >/dev/null 2>&1; then
    ts_label="$(tailscale_p_login_label)"
  elif [ -f "$SCRIPT_DIR/tailscale-p.sh" ]; then
    # shellcheck source=src/advanced/tailscale-p.sh
    source "$SCRIPT_DIR/tailscale-p.sh"
    if declare -F tailscale_p_login_label >/dev/null 2>&1; then
      ts_label="$(tailscale_p_login_label)"
    fi
  fi

  echo "狀態："
  echo " - Headscale：$hs_label"
  echo " - tailscaled：$tsd_label（tailscale：$ts_label）"
  echo " - DERP（derper）：$derp_label"
  return 0
}

headscale_p_menu() {
  _headscale_require_tty || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ Headscale / DERP（Headscale + Postgres + Headplane）❖"
    echo "=================================="
    echo "教學與文件：https://headscale.net/"
    _headscale_print_runtime_status || true
    echo "----------------------------------"
    echo "1. 部署 headscale"
    echo "2. 產生 Headscale API Key"
    echo "3. 安裝/更新 tailscale 客戶端"
    echo "4. 加入 Headscale 伺服器"
    echo "5. Tailnet 服務埠轉發"
    echo "6. 開啟 tailscale（tailscale up）"
    echo "7. 關閉 tailscale（tailscale down）"
    echo "8. 查看 tailscale status"
    echo "9. 部署/更新 DERP（derper）"
    echo "10. 注入自建 DERP（derpmap + config.yaml）"
    echo "----------------------------------"
    echo "d. 完整移除"
    echo "----------------------------------"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-10/d]: " choice

    case "$choice" in
      1) headscale_p_deploy || true ;;
      2) _headscale_create_ui_apikey_action 0 || true ;;
      3) headscale_p_install_tailscale_client || true ;;
      4) headscale_p_join_headscale_server || true ;;
      5) headscale_p_tailnet_port_forward || true ;;
      6)
        _headscale_load_tailscale_module || { ui_pause "按任意鍵返回..."; continue; }
        tailscale_p_client_enable || true
        ;;
      7)
        _headscale_load_tailscale_module || { ui_pause "按任意鍵返回..."; continue; }
        tailscale_p_client_disable || true
        ;;
      8)
        _headscale_load_tailscale_module || { ui_pause "按任意鍵返回..."; continue; }
        tailscale_p_show_status || true
        ;;
      9)
        if declare -F tgdb_load_module >/dev/null 2>&1; then
          tgdb_load_module "derper-p" || { ui_pause "按任意鍵返回..."; continue; }
        else
          # shellcheck source=src/advanced/derper-p.sh
          source "$SCRIPT_DIR/derper-p.sh"
        fi
        derper_p_deploy || true
        ;;
      10)
        if declare -F tgdb_load_module >/dev/null 2>&1; then
          tgdb_load_module "derper-p" || { ui_pause "按任意鍵返回..."; continue; }
        else
          # shellcheck source=src/advanced/derper-p.sh
          source "$SCRIPT_DIR/derper-p.sh"
        fi
        derper_p_inject_headscale_detected || true
        ;;
      d|D) headscale_p_full_remove || true ;;
      0) return 0 ;;
      *) echo "無效選項，請重新輸入。"; sleep 1 ;;
    esac
  done
}
