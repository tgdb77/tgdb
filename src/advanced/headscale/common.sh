#!/bin/bash

# Headscale 核心（含 Postgres、Headplane、Quadlet 與更新流程）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

HEADSCALE_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADSCALE_ADVANCED_DIR="$(cd "$HEADSCALE_MODULE_DIR/.." && pwd)"
SRC_ROOT="$(cd "$HEADSCALE_ADVANCED_DIR/.." && pwd)"
# 供既有內部 fallback 載入邏輯使用，值維持 src/advanced。
# shellcheck disable=SC2034 # 供其他拆分模組 fallback 載入使用
SCRIPT_DIR="$HEADSCALE_ADVANCED_DIR"

# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

HEADSCALE_CONTAINER_NAME="headscale"
# shellcheck disable=SC2034 # 供其他拆分模組引用
HEADSCALE_DEFAULT_HOST_PORT="18080"
# shellcheck disable=SC2034 # 供其他拆分模組引用
HEADSCALE_DEFAULT_UI_HOST_PORT="18081"
# shellcheck disable=SC2034 # 供其他拆分模組引用
HEADSCALE_LATEST_VERSION="0.29.1"
# shellcheck disable=SC2034 # 供其他拆分模組引用
HEADPLANE_LATEST_VERSION="0.7.0"

_headscale_resolved_unit_path() {
  local unit="$1"
  _quadlet_runtime_or_legacy_unit_path "$unit" "headscale"
}

_headscale_load_tailscale_module() {
  if declare -F tailscale_p_menu >/dev/null 2>&1; then
    return 0
  fi

  local p="$HEADSCALE_MODULE_DIR/tailscale.sh"
  if [ ! -f "$p" ]; then
    tgdb_fail "找不到 tailscale 模組：$p" 1 || true
    return 1
  fi

  # shellcheck source=src/advanced/headscale/tailscale.sh
  source "$p"
  return 0
}

_headscale_load_derper_module() {
  if declare -F derper_p_deploy >/dev/null 2>&1; then
    return 0
  fi
  # shellcheck source=src/advanced/headscale/derper.sh
  source "$HEADSCALE_MODULE_DIR/derper.sh"
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

_headscale_is_ipv4_addr() {
  local ip="${1:-}"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

_headscale_is_ipv6_addr() {
  local ip="${1:-}"
  [[ -n "$ip" ]] || return 1
  [[ "$ip" == *:* ]] || return 1
  [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]]
}

_headscale_detect_public_ipv4() {
  local ip=""

  if declare -F get_ipv4_address >/dev/null 2>&1; then
    ip="$(get_ipv4_address 2>/dev/null || true)"
    if _headscale_is_ipv4_addr "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  if command -v ip >/dev/null 2>&1; then
    ip="$(
      ip -4 route get 1 2>/dev/null | awk '{
        for (i = 1; i <= NF; i++) {
          if ($i == "src") { print $(i + 1); exit }
        }
      }' || true
    )"
    if _headscale_is_ipv4_addr "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  return 1
}

_headscale_detect_public_ipv6() {
  local ip=""

  if command -v curl >/dev/null 2>&1; then
    ip="$(
      curl -6 -fsS --connect-timeout 3 --max-time 5 https://api64.ipify.org 2>/dev/null \
        | tr -d '\r\n' \
        | head -n1 \
        || true
    )"
    ip="${ip%%%*}"
    if _headscale_is_ipv6_addr "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  if command -v ip >/dev/null 2>&1; then
    ip="$(
      ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{
        for (i = 1; i <= NF; i++) {
          if ($i == "src") {
            gsub(/%.*/, "", $(i + 1))
            print $(i + 1)
            exit
          }
        }
      }' || true
    )"
    ip="${ip%%%*}"
    if _headscale_is_ipv6_addr "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  return 1
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
      if ! _headscale_check_subdomain_dns_for_cert "$value"; then
        case "$?" in
          2) return 2 ;;
          *) continue ;;
        esac
      fi
      printf -v "$out_var" '%s' "$value"
      return 0
    fi
    tgdb_err "root_domain 格式不正確（例：example.com；不可包含空白、/、:、@）。"
  done
}

_headscale_dns_ip_list_label() {
  local lines="${1:-}"
  local joined=""

  if [ -z "${lines:-}" ]; then
    printf '%s\n' "未解析到"
    return 0
  fi

  joined="$(printf '%s\n' "$lines" | tgdb_join_lines_csv 2>/dev/null || true)"
  if [ -n "${joined:-}" ]; then
    printf '%s\n' "$joined"
  else
    printf '%s\n' "未解析到"
  fi
}

_headscale_dns_contains_ip() {
  local lines="${1:-}"
  local target_ip="${2:-}"
  [ -n "${lines:-}" ] || return 1
  [ -n "${target_ip:-}" ] || return 1
  printf '%s\n' "$lines" | grep -Fx -- "$target_ip" >/dev/null 2>&1
}

_headscale_check_subdomain_dns_for_cert() {
  local root_domain="${1:-}"
  local fqdn=""
  local public_ipv4="" public_ipv6=""
  local resolved_ipv4="" resolved_ipv6=""
  local matched=1
  local status=0

  [ -n "${root_domain:-}" ] || return 1
  fqdn="hs.${root_domain}"

  echo "----------------------------------"
  echo "檢查 ${fqdn} DNS 是否已指向本機公網 IP..."

  public_ipv4="$(_headscale_detect_public_ipv4 2>/dev/null || true)"
  public_ipv6="$(_headscale_detect_public_ipv6 2>/dev/null || true)"
  resolved_ipv4="$(tgdb_resolve_dns_ips "$fqdn" 4 2>/dev/null || true)"
  resolved_ipv6="$(tgdb_resolve_dns_ips "$fqdn" 6 2>/dev/null || true)"

  echo " - 本機公網 IPv4：${public_ipv4:-未偵測到}"
  echo " - 本機公網 IPv6：${public_ipv6:-未偵測到}"
  echo " - DNS A：$(_headscale_dns_ip_list_label "$resolved_ipv4")"
  echo " - DNS AAAA：$(_headscale_dns_ip_list_label "$resolved_ipv6")"

  if _headscale_is_ipv4_addr "$public_ipv4" && _headscale_dns_contains_ip "$resolved_ipv4" "$public_ipv4"; then
    matched=0
  fi
  if _headscale_is_ipv6_addr "$public_ipv6" && _headscale_dns_contains_ip "$resolved_ipv6" "$public_ipv6"; then
    matched=0
  fi

  if [ "$matched" -eq 0 ]; then
    echo "✅ ${fqdn} 已對到本機公網 IP，可繼續申請憑證。"
    return 0
  fi

  tgdb_warn "${fqdn} 目前尚未對到本機公網 IP，憑證申請可能失敗。"
  echo "建議先確認："
  echo " - hs 子域名的 A / AAAA 記錄是否已指向這台機器"
  echo " - 若使用 Cloudflare，請先切到 DNS only（灰雲）"
  echo " - DNS 剛修改時，請稍候數分鐘再重試"

  if ! ui_confirm_yn "仍要使用此 root_domain 繼續部署 Headscale 嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
    status=$?
    [ "$status" -eq 2 ] && return 2
    return 1
  fi
  return 0
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
  awk -v k="$key" '
    index($0, k "=") == 1 {
      value = substr($0, length(k) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value ~ /^".*"$/) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
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
  local root_domain="$1" db_user="$2" db_password="$3" public_ipv4="${4:-}" public_ipv6="${5:-}"

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
    -e 's/^    enabled: false$/    enabled: true/g' \
    "$tpl" >"$out"

  if _headscale_is_ipv4_addr "$public_ipv4"; then
    sed -i "s/^    ipv4: \".*\"$/    ipv4: \"${public_ipv4}\"/g" "$out" 2>/dev/null || true
  fi
  if _headscale_is_ipv6_addr "$public_ipv6"; then
    sed -i "s/^    ipv6: \".*\"$/    ipv6: \"${public_ipv6}\"/g" "$out" 2>/dev/null || true
  fi

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
  # Headplane 0.7.x 要求 server.cookie_secret 長度必須「剛好 32」。
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

  local src tmp tmp2 need_host
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
    -e '/^[[:space:]]*config_strict:[[:space:]]*/d' \
    -e '/^[[:space:]]*dns_records_path:[[:space:]]*/d' \
    "$src" >"$tmp"

  need_host=1
  if grep -q '^[[:space:]]*host:[[:space:]]*' "$tmp" 2>/dev/null; then
    need_host=0
  fi
  awk -v need_host="$need_host" '
    /^server:[[:space:]]*$/ {
      print
      if (need_host == 1) {
        print "  host: \"0.0.0.0\""
      }
      next
    }
    /^headscale:[[:space:]]*$/ {
      print
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
  local headscale_version="${4:-}"
  local headplane_version="${5:-}"

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

  local -a headscale_sed=(
    -e "s|\${instance_dir}|$esc_inst|g"
    -e "s|\${container_name}|$esc_cn|g"
  )
  if [ -n "$headscale_version" ]; then
    headscale_sed+=(-e "s|^Image=ghcr.io/juanfont/headscale:.*|Image=ghcr.io/juanfont/headscale:${headscale_version}|")
  fi
  sed "${headscale_sed[@]}" "$tpl_dir/default.container" >"$out_dir/${HEADSCALE_CONTAINER_NAME}.container"

  sed \
    -e "s|\${instance_dir}|$esc_inst|g" \
    -e "s|\${container_name}|$esc_cn|g" \
    "$tpl_dir/default2.container" >"$out_dir/${HEADSCALE_CONTAINER_NAME}-postgres.container"

  # Headplane（取代 headscale-ui）：使用 default3.container（避免額外檔名）
  if [ ! -f "$tpl_dir/default3.container" ]; then
    tgdb_fail "找不到 Headplane Quadlet 範本：$tpl_dir/default3.container" 1 || return $?
  fi
  local -a headplane_sed=(
    -e "s|\${instance_dir}|$esc_inst|g"
    -e "s|\${container_name}|$esc_cn|g"
    -e "s|\${user_id}|$esc_uid|g"
  )
  if [ -n "$headplane_version" ]; then
    headplane_sed+=(-e "s|^Image=ghcr.io/tale/headplane:.*|Image=ghcr.io/tale/headplane:${headplane_version}|")
  fi
  sed "${headplane_sed[@]}" "$tpl_dir/default3.container" >"$out_dir/${HEADSCALE_CONTAINER_NAME}-headplane.container"

  return 0
}

_headscale_install_quadlet_units() {
  local host_port="$1"
  local ui_host_port="$2"
  local headscale_version="${3:-}"
  local headplane_version="${4:-}"

  local tmp_dir=""
  tmp_dir="$(mktemp -d 2>/dev/null || true)"
  if [ -z "${tmp_dir:-}" ]; then
    tgdb_fail "無法建立暫存目錄（mktemp -d）" 1 || return $?
  fi

  _headscale_render_quadlet_units_to_dir "$tmp_dir" "$host_port" "$ui_host_port" "$headscale_version" "$headplane_version" || {
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
