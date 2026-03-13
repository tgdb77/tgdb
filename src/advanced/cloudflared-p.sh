#!/bin/bash

# Cloudflare Tunnel（cloudflared / Podman + Quadlet）管理模組
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

_cloudflared_repo_tpl_config() {
  printf '%s\n' "$CONFIG_DIR/cloudflared/configs/config.yml.example"
}

_cloudflared_repo_tpl_quadlet() {
  printf '%s\n' "$CONFIG_DIR/cloudflared/quadlet/default.container"
}

_cloudflared_default_image() {
  local tpl image=""
  tpl="$(_cloudflared_repo_tpl_quadlet)"

  if [ -f "$tpl" ]; then
    image="$(_quadlet_extract_images "$(cat "$tpl" 2>/dev/null || true)" | head -n 1 || true)"
  fi

  [ -n "${image:-}" ] || image="docker.io/cloudflare/cloudflared:latest"
  printf '%s\n' "$image"
}

_cloudflared_root_dir() {
  printf '%s\n' "$TGDB_DIR/cloudflared"
}

_cloudflared_auth_dir() {
  printf '%s\n' "$(_cloudflared_root_dir)/auth"
}

_cloudflared_tunnels_dir() {
  printf '%s\n' "$(_cloudflared_root_dir)/tunnels"
}

_cloudflared_ensure_layout() {
  mkdir -p "$(_cloudflared_auth_dir)" "$(_cloudflared_tunnels_dir)"
}

_cloudflared_selinux_volume_suffix() {
  if declare -F _is_selinux_enforcing >/dev/null 2>&1 && _is_selinux_enforcing; then
    echo ":Z"
    return 0
  fi
  echo ""
  return 0
}

_cloudflared_podman_supports_userns_keep_id() {
  command -v podman >/dev/null 2>&1 || return 1
  podman run --help 2>/dev/null | grep -Fq "keep-id"
}

_cloudflared_podman_user_args_for_rw_mount() {
  # rootless Podman：容器內 uid 0 通常對應 host 的呼叫者 UID。
  # 直接用 --user=<host uid> 反而會映射到 subuid，導致 bind mount 寫入失敗。
  if _cloudflared_podman_supports_userns_keep_id; then
    local uid gid
    uid="$(id -u 2>/dev/null || echo "")"
    gid="$(id -g 2>/dev/null || echo "")"
    if [[ "$uid" =~ ^[0-9]+$ ]] && [[ "$gid" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "--userns=keep-id" "--user=${uid}:${gid}"
      return 0
    fi
  fi

  # fallback：用容器內 root（對 rootless 通常安全且可寫入 host bind mount）
  printf '%s\n' "--user=0:0"
  return 0
}

_cloudflared_require_tty() {
  if ! ui_is_interactive; then
    tgdb_fail "Cloudflare Tunnel 佈署需要互動式終端（TTY）。" 2 || true
    return 2
  fi
  return 0
}

_cloudflared_require_podman() {
  if command -v podman >/dev/null 2>&1; then
    return 0
  fi
  tgdb_fail "未偵測到 Podman，Cloudflare Tunnel 需要使用 Podman 啟動 cloudflared。" 1 || true
  echo "請先到主選單：5. Podman 管理 → 安裝/更新 Podman"
  return 1
}

_cloudflared_unit_name_from_tunnel() {
  local tunnel="$1"
  local safe
  safe="$(printf '%s' "$tunnel" | sed 's/[^a-zA-Z0-9._-]/-/g; s/^-*//; s/-*$//')"
  [ -n "$safe" ] || safe="cloudflared"
  printf '%s\n' "cloudflared-${safe}"
}

_cloudflared_is_valid_tunnel_name() {
  local name="${1:-}"
  [ -n "$name" ] || return 1
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]
}

_cloudflared_is_valid_fqdn() {
  local fqdn="${1:-}"
  [ -n "$fqdn" ] || return 1
  case "$fqdn" in
    *" "*|*"/"*|*"\\"*|*":"*) return 1 ;;
  esac
  [[ "$fqdn" == *.* ]]
}

_cloudflared_is_valid_port() {
  local p="${1:-}"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

_cloudflared_tunnel_dir() {
  local tunnel="$1"
  printf '%s\n' "$(_cloudflared_tunnels_dir)/$tunnel"
}

_cloudflared_cert_path() {
  printf '%s\n' "$(_cloudflared_auth_dir)/cert.pem"
}

_cloudflared_uuid_from_text() {
  local text="$1"
  printf '%s\n' "$text" | grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n1
}

_cloudflared_detect_latest_json_uuid() {
  local auth_dir
  auth_dir="$(_cloudflared_auth_dir)"
  local f=""
  # shellcheck disable=SC2012 # 這裡僅需挑最新的 JSON 憑證檔；檔名由 cloudflared 產生且受控
  f="$(ls -t "$auth_dir"/*.json 2>/dev/null | head -n1 || true)"
  [ -n "$f" ] || return 1
  basename "${f%.json}"
}

_cloudflared_temp_login() {
  _cloudflared_require_tty || return $?
  _cloudflared_require_podman || return $?
  _cloudflared_ensure_layout

  local cert
  cert="$(_cloudflared_cert_path)"
  if [ -f "$cert" ]; then
    if ui_confirm_yn "已偵測到 cert.pem（Cloudflare 登入憑證），要重新登入覆蓋嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
      rm -f "$cert" 2>/dev/null || true
    else
      echo "已沿用既有 cert.pem。"
      return 0
    fi
  fi

  echo "=================================="
  echo "❖ Cloudflare Tunnel：登入取得 cert.pem ❖"
  echo "=================================="
  echo "接下來會使用臨時容器執行 cloudflared tunnel login。"
  echo "它會輸出一段網址，請在瀏覽器開啟並完成授權；完成後會下載 cert.pem。"
  echo "----------------------------------"

  local auth_dir vol
  auth_dir="$(_cloudflared_auth_dir)"
  vol="${auth_dir}:/tmp/.cloudflared$(_cloudflared_selinux_volume_suffix)"

  if [ ! -w "$auth_dir" ]; then
    tgdb_warn "目錄不可寫入：$auth_dir（可能是權限/擁有者問題，將嘗試 chmod u+rwx）"
    chmod u+rwx "$auth_dir" 2>/dev/null || true
  fi

  local -a user_args=()
  local a
  while IFS= read -r a; do
    [ -n "$a" ] && user_args+=("$a")
  done < <(_cloudflared_podman_user_args_for_rw_mount)

  podman run --rm -it "${user_args[@]}" \
    -v "$vol" \
    -w /tmp/.cloudflared \
    -e HOME=/tmp \
    -e TUNNEL_ORIGIN_CERT=/tmp/.cloudflared/cert.pem \
    docker.io/cloudflare/cloudflared:latest \
    tunnel login

  if [ ! -f "$cert" ]; then
    tgdb_fail "登入完成後仍找不到 cert.pem：$cert（可能未完成授權；或掛載目錄仍不可寫入：$auth_dir）" 1 || true
    return 1
  fi

  echo "✅ 已取得 cert.pem：$cert"
  return 0
}

_cloudflared_temp_create_tunnel() {
  local tunnel_name="$1"

  _cloudflared_require_podman || return $?
  _cloudflared_ensure_layout

  local cert
  cert="$(_cloudflared_cert_path)"
  if [ ! -f "$cert" ]; then
    tgdb_fail "尚未登入 Cloudflare（找不到 cert.pem）。請先執行登入。" 1 || true
    return 1
  fi

  local auth_dir
  auth_dir="$(_cloudflared_auth_dir)"
  local vol
  vol="${auth_dir}:/tmp/.cloudflared$(_cloudflared_selinux_volume_suffix)"
  local -a user_args=()
  local a
  while IFS= read -r a; do
    [ -n "$a" ] && user_args+=("$a")
  done < <(_cloudflared_podman_user_args_for_rw_mount)

  local out rc uuid
  out="$(podman run --rm "${user_args[@]}" \
    -v "$vol" \
    -w /tmp \
    -e HOME=/tmp \
    -e TUNNEL_ORIGIN_CERT=/tmp/.cloudflared/cert.pem \
    docker.io/cloudflare/cloudflared:latest \
    tunnel create "$tunnel_name" 2>&1)" || rc=$?
  rc="${rc:-0}"

  if [ "$rc" -ne 0 ]; then
    tgdb_fail "建立 Tunnel 失敗（cloudflared tunnel create）。請檢查帳號權限、Tunnel 名稱是否已存在。\n\n$out" 1 || true
    return 1
  fi

  uuid="$(_cloudflared_uuid_from_text "$out" || true)"
  if [ -z "${uuid:-}" ]; then
    uuid="$(_cloudflared_detect_latest_json_uuid || true)"
  fi

  if [ -z "${uuid:-}" ]; then
    tgdb_fail "建立 Tunnel 成功但無法解析 TUNNEL_UUID（且找不到 *.json）。輸出如下：\n\n$out" 1 || true
    return 1
  fi

  if [ ! -f "$auth_dir/${uuid}.json" ]; then
    tgdb_fail "建立 Tunnel 後找不到憑證檔：$auth_dir/${uuid}.json\n\n$out" 1 || true
    return 1
  fi

  printf '%s\n' "$uuid"
  return 0
}

_cloudflared_render_instance_config() {
  local tunnel_uuid="$1" fqdn="$2" port="$3" instance_dir="$4"

  local tpl
  tpl="$(_cloudflared_repo_tpl_config)"
  [ -f "$tpl" ] || { tgdb_fail "找不到 cloudflared config.yml 樣板：$tpl" 1 || true; return 1; }

  local cfg
  cfg="$(cat "$tpl")"

  cfg="$(printf '%s\n' "$cfg" | sed \
    -e "s|\${TUNNEL_UUID}|$(_esc "$tunnel_uuid")|g" \
    -e "s|\${fqdn}|$(_esc "$fqdn")|g" \
    -e "s|\${port}|$(_esc "$port")|g" \
  )"

  local out="$instance_dir/config.yml"
  _write_file "$out" "$cfg"
  chmod 600 "$out" 2>/dev/null || true
  printf '%s\n' "$out"
}

_cloudflared_render_quadlet_unit() {
  local unit_name="$1" container_name="$2" tunnel_name="$3" tunnel_uuid="$4" instance_dir="$5"

  local tpl
  tpl="$(_cloudflared_repo_tpl_quadlet)"
  [ -f "$tpl" ] || { tgdb_fail "找不到 cloudflared Quadlet 樣板：$tpl" 1 || true; return 1; }

  local content
  content="$(cat "$tpl")"

  content="$(printf '%s\n' "$content" | sed \
    -e "s|\${container_name}|$(_esc "$container_name")|g" \
    -e "s|\${instance_dir}|$(_esc "$instance_dir")|g" \
    -e "s|\${TUNNEL_NAME}|$(_esc "$tunnel_name")|g" \
    -e "s|\${TUNNEL_UUID}|$(_esc "$tunnel_uuid")|g" \
  )"

  _install_unit_and_enable "$unit_name" "$content"
  return 0
}

cloudflared_p_deploy() {
  _cloudflared_require_tty || return $?
  _cloudflared_require_podman || { ui_pause "按任意鍵返回..."; return 1; }

  _cloudflared_ensure_layout

  local tunnel_name=""
  while true; do
    read -r -e -p "請輸入要建立的 Tunnel 名稱（例如 tgdb-tunnel，輸入 0 取消）: " tunnel_name
    [ "$tunnel_name" = "0" ] && return 0
    if _cloudflared_is_valid_tunnel_name "$tunnel_name"; then
      break
    fi
    tgdb_err "Tunnel 名稱不合法：只允許英數、.、_、-，且需以英數開頭。"
  done

  local instance_dir
  instance_dir="$(_cloudflared_tunnel_dir "$tunnel_name")"

  local unit_name
  unit_name="$(_cloudflared_unit_name_from_tunnel "$tunnel_name")"
  local unit_path
  unit_path="$(rm_user_unit_path "$unit_name.container" 2>/dev/null || true)"

  local auth_dir
  auth_dir="$(_cloudflared_auth_dir)"

  local tunnel_uuid=""
  if [ -n "${unit_path:-}" ] && [ -f "$unit_path" ]; then
    if ! ui_confirm_yn "已存在 Quadlet 單元：$unit_path，要覆蓋並重新啟動嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      echo "操作已取消"
      ui_pause "按任意鍵返回..."
      return 0
    fi
  fi

  if [ -d "$instance_dir" ]; then
    echo "已偵測到同名 Tunnel 目錄：$instance_dir"
    if ui_confirm_yn "要使用既有目錄重新渲染設定並啟動嗎？（不會重新建立 Tunnel）(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      local f=""
      # shellcheck disable=SC2012 # 這裡僅需挑最新的 JSON 憑證檔；檔名由 cloudflared 產生且受控
      f="$(ls -t "$instance_dir"/*.json 2>/dev/null | head -n1 || true)"
      tunnel_uuid="$(basename "${f%.json}" 2>/dev/null || true)"
      if [ -z "${tunnel_uuid:-}" ] || ! [[ "$tunnel_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        tgdb_fail "找不到既有 Tunnel 憑證檔（*.json）或檔名不是 UUID：$instance_dir" 1 || true
        ui_pause "按任意鍵返回..."
        return 1
      fi
      chmod 600 "$instance_dir/${tunnel_uuid}.json" 2>/dev/null || true
      echo "✅ 已沿用既有憑證：$instance_dir/${tunnel_uuid}.json"
      echo "✅ 取得 TUNNEL_UUID=$tunnel_uuid"
    else
      echo "操作已取消"
      ui_pause "按任意鍵返回..."
      return 0
    fi
  else
    if [ -e "$instance_dir" ]; then
      tgdb_fail "已存在同名路徑且不是目錄：$instance_dir（請先移除或改用不同名稱）" 1 || true
      ui_pause "按任意鍵返回..."
      return 1
    fi

    echo "----------------------------------"
    echo "步驟 1/4：登入 Cloudflare 取得 cert.pem"
    echo "----------------------------------"
    _cloudflared_temp_login || { ui_pause "按任意鍵返回..."; return 1; }

    echo "----------------------------------"
    echo "步驟 2/4：建立 Tunnel 並取得 TUNNEL_UUID"
    echo "----------------------------------"
    tunnel_uuid="$(_cloudflared_temp_create_tunnel "$tunnel_name")" || { ui_pause "按任意鍵返回..."; return 1; }
    echo "✅ 已建立 Tunnel：TUNNEL_NAME=$tunnel_name"
    echo "✅ 取得 TUNNEL_UUID=$tunnel_uuid"

    mkdir -p "$instance_dir"

    mv "$auth_dir/${tunnel_uuid}.json" "$instance_dir/${tunnel_uuid}.json" 2>/dev/null || {
      tgdb_fail "無法搬移憑證檔到 Tunnel 目錄：$auth_dir/${tunnel_uuid}.json → $instance_dir/${tunnel_uuid}.json" 1 || true
      ui_pause "按任意鍵返回..."
      return 1
    }
    chmod 600 "$instance_dir/${tunnel_uuid}.json" 2>/dev/null || true
  fi

  echo "----------------------------------"
  echo "步驟 3/4：輸入域名與目標埠號"
  echo "----------------------------------"
  local fqdn="" port=""
  while true; do
    read -r -e -p "請輸入要綁定的完整域名（FQDN，例如 app.example.com，輸入 0 取消）: " fqdn
    if [ "$fqdn" = "0" ]; then
      echo "已取消後續設定。注意：Tunnel 已建立且憑證已保存：$instance_dir/${tunnel_uuid}.json"
	      ui_pause "按任意鍵返回..."
      return 0
    fi
    if _cloudflared_is_valid_fqdn "$fqdn"; then
      break
    fi
    tgdb_err "域名格式不正確，請輸入像 app.example.com 的完整域名（不可包含空白、:、/）。"
  done
  while true; do
    read -r -e -p "請輸入目標服務埠號（1-65535，例如 3000，輸入 0 取消）: " port
    if [ "$port" = "0" ]; then
      echo "已取消後續設定。注意：Tunnel 已建立且憑證已保存：$instance_dir/${tunnel_uuid}.json"
	      ui_pause "按任意鍵返回..."
      return 0
    fi
    if _cloudflared_is_valid_port "$port"; then
      break
    fi
    tgdb_err "埠號不合法，請輸入 1-65535 的數字。"
  done

  local config_path
  config_path="$(_cloudflared_render_instance_config "$tunnel_uuid" "$fqdn" "$port" "$instance_dir")" || {
	    ui_pause "按任意鍵返回..."
    return 1
  }

  if ui_confirm_yn "要自動建立 Cloudflare DNS Route（cloudflared tunnel route dns）嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    if [ ! -f "$(_cloudflared_cert_path)" ]; then
      tgdb_warn "尚未登入 Cloudflare（找不到 cert.pem），需要先登入才能自動建立 DNS Route。"
	      _cloudflared_temp_login || { ui_pause "按任意鍵返回..."; return 1; }
    fi
    local out rc
    local vol
    vol="${auth_dir}:/tmp/.cloudflared$(_cloudflared_selinux_volume_suffix)"
    local -a user_args=()
    local a
    while IFS= read -r a; do
      [ -n "$a" ] && user_args+=("$a")
    done < <(_cloudflared_podman_user_args_for_rw_mount)

    out="$(podman run --rm "${user_args[@]}" \
      -v "$vol" \
      -w /tmp \
      -e HOME=/tmp \
      -e TUNNEL_ORIGIN_CERT=/tmp/.cloudflared/cert.pem \
      docker.io/cloudflare/cloudflared:latest \
      tunnel route dns "$tunnel_name" "$fqdn" 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -ne 0 ]; then
      tgdb_warn "DNS Route 建立失敗（不影響本機服務啟動），請改用 Cloudflare 控制台手動新增 CNAME。\n\n$out"
    else
      echo "✅ DNS Route 已建立：$fqdn"
    fi
  else
    echo "已略過 DNS Route。"
  fi

  echo "----------------------------------"
  echo "步驟 4/4：渲染設定檔並完成佈署"
  echo "----------------------------------"
  local container_name
  container_name="$unit_name"
  _cloudflared_render_quadlet_unit "$unit_name" "$container_name" "$tunnel_name" "$tunnel_uuid" "$instance_dir" || {
	    ui_pause "按任意鍵返回..."
    return 1
  }

  echo "✅ Cloudflare Tunnel 已佈署並嘗試啟動"
  echo " - Tunnel 目錄：$instance_dir"
  echo " - 設定檔：$config_path"
  echo " - 單元名稱：$unit_name"
  echo "查看狀態/日誌："
  echo "  systemctl --user status ${unit_name}.service"
  echo "  journalctl --user -u ${unit_name}.service -n 200 --no-pager"
	  ui_pause "按任意鍵返回..."
  return 0
}



_cloudflared_list_tunnels() {
  local base
  base="$(_cloudflared_tunnels_dir)"
  [ -d "$base" ] || return 0
  find "$base" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort || true
}

_cloudflared_select_tunnel() {
  local out_var="$1"
  local -a tunnels=()
  mapfile -t tunnels < <(_cloudflared_list_tunnels)
  if [ ${#tunnels[@]} -eq 0 ]; then
    tgdb_err "目前尚未建立任何 Tunnel。"
    return 1
  fi

  echo "已建立 Tunnel："
  local i
  for i in "${!tunnels[@]}"; do
    printf '  %2d) %s\n' "$((i + 1))" "${tunnels[$i]}"
  done

  local idx
  if ! ui_prompt_index idx "請輸入 Tunnel 編號（輸入 0 取消）: " 1 "${#tunnels[@]}" "" 0; then
    return 2
  fi

  printf -v "$out_var" '%s' "${tunnels[$((idx - 1))]}"
  return 0
}

_cloudflared_is_uuid() {
  local v="${1:-}"
  [[ "$v" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

_cloudflared_parse_uuid_from_config() {
  local config_path="$1"
  [ -f "$config_path" ] || return 1

  local uuid=""
  uuid="$(
    awk '
      /^[[:space:]]*tunnel:[[:space:]]*/ {
        line=$0
        sub(/^[[:space:]]*tunnel:[[:space:]]*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        gsub(/^"|"$/, "", line)
        print line
        exit
      }
    ' "$config_path" 2>/dev/null || true
  )"
  [ -n "${uuid:-}" ] || return 1
  if _cloudflared_is_uuid "$uuid"; then
    printf '%s\n' "$uuid"
    return 0
  fi
  return 1
}

_cloudflared_find_uuid_in_instance_dir() {
  local instance_dir="$1"
  [ -d "$instance_dir" ] || return 1

  local config_path="$instance_dir/config.yml"
  local uuid=""
  uuid="$(_cloudflared_parse_uuid_from_config "$config_path" || true)"
  if [ -n "${uuid:-}" ]; then
    printf '%s\n' "$uuid"
    return 0
  fi

  local f=""
  # shellcheck disable=SC2012 # 這裡僅需挑最新的 JSON 憑證檔；檔名由 cloudflared 產生且受控
  f="$(ls -t "$instance_dir"/*.json 2>/dev/null | head -n1 || true)"
  uuid="$(basename "${f%.json}" 2>/dev/null || true)"
  if [ -n "${uuid:-}" ] && _cloudflared_is_uuid "$uuid"; then
    printf '%s\n' "$uuid"
    return 0
  fi

  return 1
}

_cloudflared_restart_unit() {
  local unit_name="$1"
  _systemctl_user_try restart --no-block -- "${unit_name}.service" "container-${unit_name}.service" && return 0
  _systemctl_user_try restart -- "${unit_name}.service" "container-${unit_name}.service" && return 0

  if command -v podman >/dev/null 2>&1; then
    podman restart "$unit_name" >/dev/null 2>&1 && return 0
  fi

  return 1
}

_cloudflared_try_delete_path() {
  local delete_path="$1"
  [ -n "$delete_path" ] || return 0

  if command -v podman >/dev/null 2>&1; then
    if ! podman unshare rm -rf "$delete_path" 2>/dev/null; then
      if [ -d "$delete_path" ]; then
        tgdb_warn "無法刪除資料夾：$delete_path"
        tgdb_warn "可能因權限不足（例如容器以 root 建立檔案），請使用 sudo 或 root 手動清理。"
        return 1
      fi
    fi
    return 0
  fi

  if ! rm -rf "$delete_path" 2>/dev/null; then
    if [ -d "$delete_path" ]; then
      tgdb_warn "無法刪除資料夾：$delete_path"
      tgdb_warn "可能因權限不足，請使用 sudo 或 root 手動清理。"
      return 1
    fi
  fi
  return 0
}

_cloudflared_prompt_delete_dir() {
  local out_var="$1"
  local delete_path="$2"
  local what="${3:-目錄}"

  if ui_confirm_yn "是否刪除${what}（$delete_path）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    printf -v "$out_var" '%s' "y"
    return 0
  fi

  local rc=$?
  if [ "$rc" -eq 2 ]; then
    return 2
  fi
  printf -v "$out_var" '%s' "n"
  return 0
}

cloudflared_p_list() {
  _cloudflared_ensure_layout
  echo "=================================="
  echo "❖ Cloudflare Tunnel：已建立列表 ❖"
  echo "=================================="
  local -a tunnels=()
  mapfile -t tunnels < <(_cloudflared_list_tunnels)
  if [ ${#tunnels[@]} -eq 0 ]; then
    echo "（尚未建立任何 Tunnel）"
    ui_pause "按任意鍵返回..."
    return 0
  fi

  local t
  for t in "${tunnels[@]}"; do
    local unit_name
    unit_name="$(_cloudflared_unit_name_from_tunnel "$t")"
    printf '%-28s %s\n' "$t" "單元：$unit_name"
  done
  ui_pause "按任意鍵返回..."
  return 0
}

cloudflared_p_update() {
  _cloudflared_require_tty || return $?
  _cloudflared_require_podman || { ui_pause "按任意鍵返回..."; return 1; }
  _cloudflared_ensure_layout

  local tunnel=""
  if ! _cloudflared_select_tunnel tunnel; then
    [ "$?" -eq 2 ] && return 0
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local instance_dir
  instance_dir="$(_cloudflared_tunnel_dir "$tunnel")"
  local unit_name
  unit_name="$(_cloudflared_unit_name_from_tunnel "$tunnel")"
  local unit_path
  unit_path="$(_quadlet_user_units_dir)/${unit_name}.container"
  if [ ! -f "$unit_path" ] && ! podman container exists "$unit_name" 2>/dev/null; then
    tgdb_fail "找不到已部署的 Tunnel 單元：$unit_name。請先完成佈署後再試。" 1 || true
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "=================================="
  echo "❖ Cloudflare Tunnel：更新映像並重啟 ❖"
  echo "=================================="
  echo "Tunnel：$tunnel"
  echo "單元：$unit_name"
  echo "目錄：$instance_dir"
  echo "----------------------------------"

  local image
  image="$(_cloudflared_default_image)"
  echo "正在拉取最新映像：$image"
  if ! podman pull "$image"; then
    tgdb_warn "拉取映像失敗：$image（將繼續嘗試重啟；若本機已有映像仍可能成功）"
  fi

  if _cloudflared_restart_unit "$unit_name"; then
    echo "✅ 已嘗試拉取最新映像並重啟"
  else
    tgdb_warn "已完成映像拉取，但重啟失敗，請手動檢查單元狀態與日誌。"
  fi
  echo "查看狀態/日誌："
  echo "  systemctl --user status ${unit_name}.service"
  echo "  journalctl --user -u ${unit_name}.service -n 200 --no-pager"
	  ui_pause "按任意鍵返回..."
  return 0
}

cloudflared_p_edit_config() {
  _cloudflared_require_tty || return $?
  _cloudflared_ensure_layout

  local tunnel=""
  if ! _cloudflared_select_tunnel tunnel; then
    [ "$?" -eq 2 ] && return 0
	    ui_pause "按任意鍵返回..."
    return 1
  fi

  local instance_dir
  instance_dir="$(_cloudflared_tunnel_dir "$tunnel")"
  local config_path="$instance_dir/config.yml"

  if [ ! -f "$config_path" ]; then
    tgdb_warn "找不到 $config_path，將嘗試建立一份新設定。"
    local tunnel_uuid=""
    tunnel_uuid="$(_cloudflared_find_uuid_in_instance_dir "$instance_dir" || true)"
    if [ -z "${tunnel_uuid:-}" ]; then
      tgdb_fail "無法建立設定：找不到 TUNNEL_UUID（*.json / config.yml）" 1 || true
	      ui_pause "按任意鍵返回..."
      return 1
    fi

    local fqdn="" port=""
    while true; do
      read -r -e -p "請輸入要綁定的完整域名（FQDN，例如 app.example.com，輸入 0 取消）: " fqdn
      [ "$fqdn" = "0" ] && return 0
      _cloudflared_is_valid_fqdn "$fqdn" && break
      tgdb_err "域名格式不正確，請重新輸入。"
    done
    while true; do
      read -r -e -p "請輸入目標服務埠號（1-65535，例如 3000，輸入 0 取消）: " port
      [ "$port" = "0" ] && return 0
      _cloudflared_is_valid_port "$port" && break
      tgdb_err "埠號不合法，請重新輸入。"
    done

    _cloudflared_render_instance_config "$tunnel_uuid" "$fqdn" "$port" "$instance_dir" >/dev/null || {
	    ui_pause "按任意鍵返回..."
      return 1
    }
  fi

  if ! ensure_editor; then
    tgdb_fail "找不到可用編輯器（請安裝 nano/vim/vi 或設定 EDITOR）。" 1 || true
	  ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "→ 啟動編輯器: $EDITOR（完成後儲存並離開）"
  "$EDITOR" "$config_path"

  local unit_name
  unit_name="$(_cloudflared_unit_name_from_tunnel "$tunnel")"
  if ui_confirm_yn "要重啟 Tunnel 讓設定生效嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    _cloudflared_restart_unit "$unit_name"
    echo "✅ 已嘗試重啟：$unit_name"
  else
    echo "已略過重啟。"
  fi

	      ui_pause "按任意鍵返回..."
  return 0
}

cloudflared_p_full_remove() {
  _cloudflared_require_tty || return $?

  local root_dir
  root_dir="$(_cloudflared_root_dir)"

  echo "=================================="
  echo "❖ Cloudflare Tunnel：完整移除 ❖"
  echo "=================================="
  echo "此操作會停止所有 Tunnel 單元並移除 Quadlet 單元檔。"
  echo "預設也會刪除持久化目錄：$root_dir"
  echo "（不會自動刪除 Cloudflare 端的 Tunnel，需自行於控制台處理）"
  echo "----------------------------------"

  local deld="y"
  if ! _cloudflared_prompt_delete_dir deld "$root_dir" "持久化目錄"; then
    if [ "$?" -eq 2 ]; then
      echo "操作已取消"
	  ui_pause "按任意鍵返回..."
      return 0
    fi
  fi

  local -a tunnels=()
  mapfile -t tunnels < <(_cloudflared_list_tunnels)
  local t unit_name unit_path
  for t in "${tunnels[@]}"; do
    [ -n "$t" ] || continue
    unit_name="$(_cloudflared_unit_name_from_tunnel "$t")"
    _systemctl_user_try stop --no-block -- "${unit_name}.service" "container-${unit_name}.service" "${unit_name}.container" || true
    _systemctl_user_try disable -- "${unit_name}.container" "${unit_name}.service" "container-${unit_name}.service" || true
    podman rm -f "$unit_name" 2>/dev/null || true
    unit_path="$(rm_user_unit_path "${unit_name}.container" 2>/dev/null || true)"
    if [ -n "${unit_path:-}" ] && [ -f "$unit_path" ]; then
      rm -f "$unit_path" 2>/dev/null || true
    fi
  done
  _systemctl_user_try daemon-reload || true

  if [[ "$deld" =~ ^[Yy]$ ]]; then
    if [ -d "$root_dir" ]; then
      _cloudflared_try_delete_path "$root_dir" || true
    fi
    echo "✅ 已移除並刪除持久化目錄：$root_dir"
  else
    echo "✅ 已移除所有單元，已保留持久化目錄：$root_dir"
  fi

	  ui_pause "按任意鍵返回..."
  return 0
}

cloudflared_p_remove() {
  _cloudflared_require_tty || return $?

  local tunnel=""
  if ! _cloudflared_select_tunnel tunnel; then
    [ "$?" -eq 2 ] && return 0
	    ui_pause "按任意鍵返回..."
    return 1
  fi

  local unit_name
  unit_name="$(_cloudflared_unit_name_from_tunnel "$tunnel")"
  local instance_dir
  instance_dir="$(_cloudflared_tunnel_dir "$tunnel")"

  echo "即將移除："
  echo " - Tunnel：$tunnel"
  echo " - 單元：$unit_name"
  echo " - 目錄：$instance_dir"
  local deld="y"
  if ! _cloudflared_prompt_delete_dir deld "$instance_dir" "Tunnel 資料夾"; then
    if [ "$?" -eq 2 ]; then
      echo "操作已取消"
	      ui_pause "按任意鍵返回..."
	      return 0
	    fi
	  fi

  _systemctl_user_try stop --no-block -- "${unit_name}.service" "container-${unit_name}.service" "${unit_name}.container" || true
  _systemctl_user_try disable -- "${unit_name}.container" "${unit_name}.service" "container-${unit_name}.service" || true
  podman rm -f "$unit_name" 2>/dev/null || true

  local unit_path=""
  unit_path="$(rm_user_unit_path "${unit_name}.container" 2>/dev/null || true)"
  if [ -n "${unit_path:-}" ] && [ -f "$unit_path" ]; then
    rm -f "$unit_path" 2>/dev/null || true
  fi
  _systemctl_user_try daemon-reload || true

  if [[ "$deld" =~ ^[Yy]$ ]]; then
    if [ -d "$instance_dir" ]; then
      _cloudflared_try_delete_path "$instance_dir" || true
    fi
  fi

  echo "✅ 已移除（如需同步刪除 Cloudflare 端 Tunnel，請至 Cloudflare 控制台並一併移除DNS紀錄）。"
  ui_pause "按任意鍵返回..."
  return 0
}

cloudflared_p_logs() {
  _cloudflared_require_tty || return $?
  _cloudflared_ensure_layout

  local tunnel=""
  if ! _cloudflared_select_tunnel tunnel; then
    [ "$?" -eq 2 ] && return 0
	    ui_pause "按任意鍵返回..."
    return 1
  fi

  local unit_name
  unit_name="$(_cloudflared_unit_name_from_tunnel "$tunnel")"
  echo "=================================="
  echo "❖ Cloudflare Tunnel：日誌（$unit_name）❖"
  echo "=================================="
  journalctl --user -u "${unit_name}.service" -n 200 --no-pager 2>/dev/null || {
    tgdb_warn "無法讀取日誌（可能尚未啟動 systemd user 或單元名稱不同）。可手動嘗試：journalctl --user -xe"
  }
	  ui_pause "按任意鍵返回..."
  return 0
}

cloudflared_p_menu() {
  _cloudflared_require_tty || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ Cloudflare Tunnel（cloudflared）❖"
    echo "教學與文件：https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/"
    echo "=================================="
    local -a tunnels=()
    mapfile -t tunnels < <(_cloudflared_list_tunnels)
    if [ ${#tunnels[@]} -eq 0 ]; then
      echo "已建立 Tunnel： （尚無）"
    else
      echo "已建立 Tunnel："
      local t
      for t in "${tunnels[@]}"; do
        [ -n "$t" ] || continue
        printf ' - %-20s 單元：%s\n' "$t" "$(_cloudflared_unit_name_from_tunnel "$t")"
      done
    fi
    echo "----------------------------------"
    echo "1. 新增/佈署 Tunnel"
    echo "2. 更新映像並重啟 Tunnel"
    echo "3. 編輯 Tunnel config.yml"
    echo "4. 查看 Tunnel 日誌"
    echo "5. 移除 Tunnel"
    echo "----------------------------------"
    echo "d. 完整移除"
    echo "----------------------------------"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-5/d]: " choice

    case "$choice" in
      1) cloudflared_p_deploy || true ;;
      2) cloudflared_p_update || true ;;
      3) cloudflared_p_edit_config || true ;;
      4) cloudflared_p_logs || true ;;
      5) cloudflared_p_remove || true ;;
      d|D) cloudflared_p_full_remove || true ;;
      0) return 0 ;;
      *) echo "無效選項，請重新輸入。"; sleep 1 ;;
    esac
  done
}
