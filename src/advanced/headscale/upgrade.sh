_headscale_deployed_version() {
  local image version
  image="$(podman inspect --format '{{.Config.Image}}' "$HEADSCALE_CONTAINER_NAME" 2>/dev/null || true)"
  version="$(printf '%s\n' "$image" | sed -n 's#^ghcr\.io/juanfont/headscale:\([0-9][0-9.]*\)$#\1#p')"
  if [ -n "$version" ]; then
    printf '%s\n' "$version"
    return 0
  fi

  podman exec "$HEADSCALE_CONTAINER_NAME" headscale version 2>/dev/null |
    sed -n 's/.*\b\([0-9]\+\.[0-9]\+\.[0-9]\+\)\b.*/\1/p' | head -n 1
}

_headscale_deployed_headplane_version() {
  podman inspect --format '{{.Config.Image}}' "${HEADSCALE_CONTAINER_NAME}-headplane" 2>/dev/null |
    sed -n 's#^ghcr\.io/tale/headplane:\([0-9][0-9.]*\)$#\1#p' | head -n 1
}

_headscale_next_upgrade_version() {
  local current="$1"
  case "$current" in
    0.27.1) printf '%s\n' '0.28.0' ;;
    0.28.*) printf '%s\n' "$HEADSCALE_LATEST_VERSION" ;;
    0.29.0) printf '%s\n' "$HEADSCALE_LATEST_VERSION" ;;
    "$HEADSCALE_LATEST_VERSION") return 2 ;;
    *) return 1 ;;
  esac
}

_headscale_upgrade_backup() {
  local from_version="$1" to_version="$2" headplane_version="$3"
  local instance_dir env_path backup_dir timestamp db_user db_name db_password
  instance_dir="$(_headscale_instance_dir)"
  env_path="$(_headscale_env_path)"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_dir="$instance_dir/backups/upgrade-${timestamp}-${from_version}-to-${to_version}"

  [ -f "$env_path" ] || { tgdb_err "找不到 PostgreSQL 設定檔：$env_path"; return 1; }
  db_user="$(_headscale_env_get "$env_path" "POSTGRES_USER" || true)"
  db_name="$(_headscale_env_get "$env_path" "POSTGRES_DB" || true)"
  db_password="$(_headscale_env_get "$env_path" "POSTGRES_PASSWORD" || true)"
  [ -n "$db_user" ] && [ -n "$db_name" ] && [ -n "$db_password" ] || {
    tgdb_err "無法從 .env 取得 PostgreSQL 備份所需設定。"
    return 1
  }

  mkdir -p "$backup_dir" || return 1
  chmod 700 "$backup_dir" 2>/dev/null || true
  cp -a "$instance_dir/etc" "$backup_dir/etc" || return 1
  cp -a "$instance_dir/lib" "$backup_dir/lib" || return 1
  cp -a "$instance_dir/headplane" "$backup_dir/headplane" || return 1
  cp -a "$env_path" "$backup_dir/.env" || return 1

  echo "正在匯出 PostgreSQL 資料庫備份..." >&2
  if ! podman exec -e PGPASSWORD="$db_password" "${HEADSCALE_CONTAINER_NAME}-postgres" \
    pg_dump -h 127.0.0.1 -p 5432 -U "$db_user" -d "$db_name" -Fc >"$backup_dir/headscale.postgres.dump"; then
    rm -f "$backup_dir/headscale.postgres.dump" 2>/dev/null || true
    tgdb_err "PostgreSQL 備份失敗，已取消升級。"
    return 1
  fi

  {
    echo "from=$from_version"
    echo "to=$to_version"
    echo "headplane_version=$headplane_version"
    echo "created_at=$(date -Is)"
    echo "database_dump=headscale.postgres.dump"
  } >"$backup_dir/metadata"
  chmod 600 "$backup_dir/.env" "$backup_dir/headscale.postgres.dump" "$backup_dir/metadata" 2>/dev/null || true
  printf '%s\n' "$backup_dir"
}

_headscale_upgrade_restore() {
  local backup_dir="$1" headscale_version="$2" headplane_version="$3" host_port="$4" ui_host_port="$5"
  local instance_dir env_path db_user db_name db_password
  instance_dir="$(_headscale_instance_dir)"
  env_path="$backup_dir/.env"
  db_user="$(_headscale_env_get "$env_path" "POSTGRES_USER" || true)"
  db_name="$(_headscale_env_get "$env_path" "POSTGRES_DB" || true)"
  db_password="$(_headscale_env_get "$env_path" "POSTGRES_PASSWORD" || true)"
  [ -n "$db_user" ] && [ -n "$db_name" ] && [ -n "$db_password" ] || return 1

  echo "正在還原 Headscale $headscale_version..."
  _systemctl_user_try stop -- \
    "container-${HEADSCALE_CONTAINER_NAME}-headplane.service" "${HEADSCALE_CONTAINER_NAME}-headplane.service" || true
  _systemctl_user_try stop -- \
    "container-${HEADSCALE_CONTAINER_NAME}.service" "${HEADSCALE_CONTAINER_NAME}.service" || true

  cp -a "$backup_dir/etc/." "$instance_dir/etc/" || return 1
  cp -a "$backup_dir/lib/." "$instance_dir/lib/" || return 1
  cp -a "$backup_dir/headplane/." "$instance_dir/headplane/" || return 1
  cp -a "$backup_dir/.env" "$instance_dir/.env" || return 1
  if ! podman exec -i -e PGPASSWORD="$db_password" "${HEADSCALE_CONTAINER_NAME}-postgres" \
    pg_restore -h 127.0.0.1 -p 5432 -U "$db_user" -d "$db_name" \
    --clean --if-exists --no-owner <"$backup_dir/headscale.postgres.dump"; then
    tgdb_err "PostgreSQL 還原失敗，請保留備份並人工處理：$backup_dir"
    return 1
  fi

  _headscale_install_quadlet_units "$host_port" "$ui_host_port" "$headscale_version" "$headplane_version" || return 1
  _headscale_upgrade_healthcheck "$headscale_version"
}

_headscale_remove_old_image() {
  local image="$1"
  [ -n "$image" ] || return 0
  if podman image rm "$image" >/dev/null 2>&1; then
    echo "🧹 已移除舊映像：$image"
  else
    tgdb_warn "未移除舊映像（可能仍被其他容器使用）：$image"
  fi
}

_headscale_upgrade_config_for_version() {
  local target_version="$1" config_path tmp randomize_client_port
  config_path="$(_headscale_config_path)"
  [ "$target_version" = "$HEADSCALE_LATEST_VERSION" ] || return 0

  randomize_client_port="$(sed -n 's/^[[:space:]]*randomize_client_port:[[:space:]]*\([^#[:space:]]*\).*/\1/p' "$config_path" | head -n 1)"
  case "$randomize_client_port" in
    true)
      tgdb_err "Headscale 0.29 已移除 randomize_client_port=true。請先在 policy 加入 randomizeClientPort: true，再執行升級。"
      return 1
      ;;
    false|"")
      sed -i '/^[[:space:]]*randomize_client_port:[[:space:]]*/d' "$config_path" || return 1
      ;;
    *)
      tgdb_err "無法判讀 randomize_client_port 的值：$randomize_client_port"
      return 1
      ;;
  esac

  grep -q '^[[:space:]]*ephemeral_node_inactivity_timeout:' "$config_path" 2>/dev/null || return 0
  if grep -q '^[[:space:]]*node:[[:space:]]*$' "$config_path" 2>/dev/null; then
    tgdb_err "偵測到舊版 ephemeral 設定與既有 node 區段，無法安全自動合併：$config_path"
    return 1
  fi

  tmp="$(mktemp 2>/dev/null || echo "${config_path}.tmp")"
  awk '
    /^[[:space:]]*ephemeral_node_inactivity_timeout:[[:space:]]*/ {
      print "node:"
      print "  ephemeral:"
      sub(/^[[:space:]]*ephemeral_node_inactivity_timeout:[[:space:]]*/, "")
      print "    inactivity_timeout: " $0
      next
    }
    { print }
  ' "$config_path" >"$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$config_path" || { rm -f "$tmp"; return 1; }
  echo "✅ 已遷移 Headscale 0.29 的 ephemeral node 設定。"
}

_headscale_upgrade_policy_preflight() {
  local target_version="$1" backup_dir="$2" policy_file config_path preflight_config tmp randomize_client_port
  policy_file="$backup_dir/policy.hujson"
  config_path="$(_headscale_config_path)"
  preflight_config="$backup_dir/preflight-config.yaml"

  if [ "$target_version" = "0.28.0" ]; then
    echo "正在備份 ACL policy..." >&2
  else
    echo "正在匯出並檢查 ACL policy..." >&2
  fi
  if ! podman exec "$HEADSCALE_CONTAINER_NAME" \
    headscale policy get --force --bypass-grpc-and-access-database-directly >"$policy_file"; then
    rm -f "$policy_file" 2>/dev/null || true
    tgdb_err "無法匯出目前的 ACL policy，已取消升級。"
    return 1
  fi

  # Headscale 0.28 的 policy check 尚未提供 direct-database 模式，
  # 因此僅保留可修復用的 policy 備份，不執行不可靠的預檢。
  if [ "$target_version" = "0.28.0" ]; then
    chmod 600 "$policy_file" 2>/dev/null || true
    tgdb_warn "Headscale 0.28 無法離線預檢 ACL；已備份 policy，將在啟動時由 0.28 驗證。"
    return 0
  fi

  cp -a "$config_path" "$preflight_config" || {
    tgdb_err "無法建立 Headscale 設定預檢副本，已取消升級。"
    return 1
  }

  # 0.29 會移除舊的 ephemeral 設定；預檢副本先套用相同轉換，避免
  # 目標映像因設定欄位過時而無法真正驗證 ACL policy。
  if [ "$target_version" = "$HEADSCALE_LATEST_VERSION" ] && \
     grep -q '^[[:space:]]*ephemeral_node_inactivity_timeout:' "$preflight_config" 2>/dev/null; then
    if grep -q '^[[:space:]]*node:[[:space:]]*$' "$preflight_config" 2>/dev/null; then
      tgdb_err "預檢設定同時含舊版 ephemeral 與 node 區段，無法安全合併。"
      return 1
    fi
    tmp="$(mktemp 2>/dev/null || echo "${preflight_config}.tmp")"
    awk '
      /^[[:space:]]*ephemeral_node_inactivity_timeout:[[:space:]]*/ {
        print "node:"
        print "  ephemeral:"
        sub(/^[[:space:]]*ephemeral_node_inactivity_timeout:[[:space:]]*/, "")
        print "    inactivity_timeout: " $0
        next
      }
      { print }
    ' "$preflight_config" >"$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$preflight_config" || { rm -f "$tmp"; return 1; }
  fi
  if [ "$target_version" = "$HEADSCALE_LATEST_VERSION" ]; then
    randomize_client_port="$(sed -n 's/^[[:space:]]*randomize_client_port:[[:space:]]*\([^#[:space:]]*\).*/\1/p' "$preflight_config" | head -n 1)"
    case "$randomize_client_port" in
      true)
        tgdb_err "Headscale 0.29 已移除 randomize_client_port=true；請先轉為 policy 的 randomizeClientPort。"
        return 1
        ;;
      false|"")
        sed -i '/^[[:space:]]*randomize_client_port:[[:space:]]*/d' "$preflight_config" || return 1
        ;;
      *)
        tgdb_err "無法判讀 randomize_client_port 的值：$randomize_client_port"
        return 1
        ;;
    esac
  fi
  chmod 600 "$policy_file" "$preflight_config" 2>/dev/null || true

  if ! podman run --rm --pod "$HEADSCALE_CONTAINER_NAME" \
    --entrypoint /ko-app/headscale \
    -v "$backup_dir:/backup:ro" \
    "ghcr.io/juanfont/headscale:${target_version}" \
    policy check --file /backup/policy.hujson \
    --bypass-grpc-and-access-database-directly --force \
    --config=/backup/preflight-config.yaml; then
    tgdb_err "ACL policy 不相容 Headscale $target_version，未變更已部署版本。"
    tgdb_err "請修正並驗證備份檔後再升級：$policy_file"
    tgdb_err "建議使用：headscale policy check --file <檔案>"
    return 1
  fi
  echo "✅ ACL policy 通過 Headscale $target_version 預檢。"
}

_headscale_upgrade_healthcheck() {
  local target_version="$1" version="" attempts=0
  while [ "$attempts" -lt 15 ]; do
    version="$(_headscale_deployed_version 2>/dev/null || true)"
    if [ "$version" = "$target_version" ] && podman exec "$HEADSCALE_CONTAINER_NAME" headscale nodes list >/dev/null 2>&1; then
      echo "✅ Headscale $target_version 已啟動，節點資料可讀取。"
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  tgdb_err "升級後健康檢查失敗，正在自動還原升級前版本，查看日誌後修正錯誤再嘗試。"
  return 1
}

_headscale_upgrade_one_step() {
  local current_version="$1" target_version="$2"
  local ports host_port ui_host_port backup_dir root_domain headplane_version
  ports="$(_headscale_read_ports_from_installed_pod_unit 2>/dev/null || true)"
  host_port="${ports%,*}"
  ui_host_port="${ports#*,}"
  [ -n "$host_port" ] && [ "$host_port" != "$ports" ] || host_port="$HEADSCALE_DEFAULT_HOST_PORT"
  [ -n "$ui_host_port" ] && [ "$ui_host_port" != "$ports" ] || ui_host_port="$HEADSCALE_DEFAULT_UI_HOST_PORT"

  echo "----------------------------------"
  echo "Headscale：$current_version → $target_version"
  if [ "$target_version" = "0.28.0" ]; then
    tgdb_warn "此版本會遷移節點 Tags；請先確認 policy 的 tagOwners 設定正確。"
  fi
  if [ "$target_version" = "$HEADSCALE_LATEST_VERSION" ]; then
    tgdb_warn "此版本會套用新的 ACL／SSH 規則驗證；請先確認既有 SSH policy。"
  fi

  headplane_version="$(_headscale_deployed_headplane_version 2>/dev/null || true)"
  [ -n "$headplane_version" ] || headplane_version="$HEADPLANE_LATEST_VERSION"
  backup_dir="$(_headscale_upgrade_backup "$current_version" "$target_version" "$headplane_version")" || return 1
  echo "✅ 備份完成：$backup_dir"
  if ! _headscale_upgrade_policy_preflight "$target_version" "$backup_dir"; then
    return 1
  fi
  if ! _headscale_upgrade_config_for_version "$target_version"; then
    _headscale_upgrade_restore "$backup_dir" "$current_version" "$headplane_version" "$host_port" "$ui_host_port" || \
      tgdb_err "自動還原失敗，請使用備份人工還原：$backup_dir"
    return 1
  fi
  root_domain="$(_headscale_detect_root_domain_from_config 2>/dev/null || true)"
  _headscale_render_headplane_config_yaml "$root_domain" "$ui_host_port" || return 1

  _systemctl_user_try stop -- \
    "container-${HEADSCALE_CONTAINER_NAME}-headplane.service" "${HEADSCALE_CONTAINER_NAME}-headplane.service" || true
  _systemctl_user_try stop -- \
    "container-${HEADSCALE_CONTAINER_NAME}.service" "${HEADSCALE_CONTAINER_NAME}.service" || true

  if ! _headscale_install_quadlet_units "$host_port" "$ui_host_port" "$target_version" "$HEADPLANE_LATEST_VERSION"; then
    _headscale_upgrade_restore "$backup_dir" "$current_version" "$headplane_version" "$host_port" "$ui_host_port" || \
      tgdb_err "自動還原失敗，請使用備份人工還原：$backup_dir"
    return 1
  fi
  if ! _headscale_upgrade_healthcheck "$target_version"; then
    _headscale_upgrade_restore "$backup_dir" "$current_version" "$headplane_version" "$host_port" "$ui_host_port" || \
      tgdb_err "自動還原失敗，請使用備份人工還原：$backup_dir"
    return 1
  fi
  _headscale_remove_old_image "ghcr.io/juanfont/headscale:${current_version}"
  if [ "$headplane_version" != "$HEADPLANE_LATEST_VERSION" ]; then
    _headscale_remove_old_image "ghcr.io/tale/headplane:${headplane_version}"
  fi
  return 0
}

_headscale_refresh_headplane_config() {
  local ports ui_host_port root_domain
  ports="$(_headscale_read_ports_from_installed_pod_unit 2>/dev/null || true)"
  ui_host_port="${ports#*,}"
  [ -n "$ui_host_port" ] && [ "$ui_host_port" != "$ports" ] || ui_host_port="$HEADSCALE_DEFAULT_UI_HOST_PORT"
  root_domain="$(_headscale_detect_root_domain_from_config 2>/dev/null || true)"
  _headscale_render_headplane_config_yaml "$root_domain" "$ui_host_port" || return 1
  _systemctl_user_try restart -- \
    "${HEADSCALE_CONTAINER_NAME}-headplane.service" "container-${HEADSCALE_CONTAINER_NAME}-headplane.service"
}

headscale_p_upgrade_deployed() {
  _headscale_require_tty || return $?
  _headscale_require_podman_for_quadlet || { ui_pause "按任意鍵返回..."; return 1; }
  if ! podman container exists "$HEADSCALE_CONTAINER_NAME" 2>/dev/null; then
    tgdb_warn "尚未部署 Headscale，無法執行更新。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  local current_version target_version rc
  current_version="$(_headscale_deployed_version 2>/dev/null || true)"
  if [ -z "$current_version" ]; then
    tgdb_err "無法辨識目前 Headscale 版本；為保護資料，已取消更新。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "❖ 已部署 Headscale 更新 ❖"
  echo "目前版本：$current_version"
  echo "目標版本：$HEADSCALE_LATEST_VERSION"
  echo "會逐 minor 升級，且每一步均建立 PostgreSQL／設定／金鑰備份。"
  echo "⚠️ 0.28 會遷移節點 Tags，請先確認 policy 的 tagOwners 設定正確。"
  echo "⚠️ 0.29 會套用新的 ACL／SSH 規則驗證，請先確認既有 SSH policy。"
  if ! ui_confirm_yn "要開始自動升級至 $HEADSCALE_LATEST_VERSION 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    echo "已取消升級。"
    ui_pause "按任意鍵返回..."
    return 0
  fi

  while :; do
    target_version="$(_headscale_next_upgrade_version "$current_version" 2>/dev/null || true)"
    if [ -z "$target_version" ]; then
      if [ "$current_version" = "$HEADSCALE_LATEST_VERSION" ]; then
        echo "✅ 已是最新支援版本。"
        if _headscale_refresh_headplane_config; then
          echo "✅ 已更新並重啟 Headplane UI 設定。"
          rc=0
        else
          tgdb_err "Headplane UI 設定更新或重啟失敗。"
          rc=1
        fi
      else
        tgdb_err "目前僅支援從 0.27.1、0.28.x 或 0.29.0 升級；偵測到：$current_version"
        rc=1
      fi
      break
    fi
    _headscale_upgrade_one_step "$current_version" "$target_version" || {
      rc=$?
      break
    }
    current_version="$target_version"
  done
  ui_pause "按任意鍵返回..."
  return "${rc:-1}"
}

