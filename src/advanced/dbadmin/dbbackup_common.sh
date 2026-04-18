#!/bin/bash

# 數據庫備份：共用工具
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DBBACKUP_COMMON_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DBBACKUP_COMMON_LOADED=1

DBBACKUP_MAX_KEEP=5
DBBACKUP_PROJECT_SUBDIR="db-dump"
DBBACKUP_DB_READY_TIMEOUT=120
DBBACKUP_DB_READY_INTERVAL=2

_dbbackup_config_dir() {
  if declare -F rm_service_dir >/dev/null 2>&1; then
    rm_service_dir "dbadmin"
    return 0
  fi

  local persist_dir
  persist_dir="$(rm_persist_config_dir 2>/dev/null || echo "")"
  [ -n "${persist_dir:-}" ] || return 1
  printf '%s\n' "$persist_dir/dbadmin"
}

_dbbackup_config_file() {
  local dir
  dir="$(_dbbackup_config_dir 2>/dev/null || true)"
  [ -n "${dir:-}" ] || return 1
  printf '%s\n' "$dir/dbbackup.conf"
}

_dbbackup_ensure_module_config() {
  local dir file
  dir="$(_dbbackup_config_dir 2>/dev/null || true)"
  file="$(_dbbackup_config_file 2>/dev/null || true)"
  [ -n "${dir:-}" ] || return 1
  [ -n "${file:-}" ] || return 1

  mkdir -p "$dir" 2>/dev/null || true
  [ -f "$file" ] || touch "$file" 2>/dev/null || true
}

_dbbackup_max_keep_get() {
  _dbbackup_ensure_module_config >/dev/null 2>&1 || {
    printf '%s\n' "$DBBACKUP_MAX_KEEP"
    return 0
  }

  local file v
  file="$(_dbbackup_config_file 2>/dev/null || true)"
  v="$(_read_kv_or_default "dbbackup_max_keep" "$file" "$DBBACKUP_MAX_KEEP")"
  if [[ "$v" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$v"
  else
    printf '%s\n' "$DBBACKUP_MAX_KEEP"
  fi
}

_dbbackup_max_keep_set() {
  local count="$1"
  local file
  _dbbackup_ensure_module_config >/dev/null 2>&1 || return 1
  file="$(_dbbackup_config_file 2>/dev/null || true)"
  [ -n "${file:-}" ] || return 1

  if grep -q '^dbbackup_max_keep=' "$file" 2>/dev/null; then
    sed -i "s|^dbbackup_max_keep=.*$|dbbackup_max_keep=$count|" "$file" 2>/dev/null || true
  else
    printf 'dbbackup_max_keep=%s\n' "$count" >>"$file"
  fi
}

dbbackup_retention_config_interactive() {
  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi

  local cur_keep new_keep default_keep
  cur_keep="$(_dbbackup_max_keep_get)"
  default_keep="$DBBACKUP_MAX_KEEP"

  echo "目前熱備份保留數量：$cur_keep"

  while true; do
    read -r -e -p "輸入熱備份保留數量（正整數，直接按 Enter 使用預設 $default_keep）: " new_keep
    new_keep="${new_keep:-$default_keep}"
    if [[ "$new_keep" =~ ^[1-9][0-9]*$ ]]; then
      break
    fi
    tgdb_err "請輸入正整數。"
  done

  _dbbackup_max_keep_set "$new_keep" || {
    tgdb_fail "更新熱備份保留數量失敗。" 1 || return $?
  }
  echo "✅ 已更新熱備份保留數量：$new_keep"
  echo "ℹ️ 新設定會在之後建立新熱備份時套用。"
}

_dbbackup_is_noninteractive() {
  if [ "${TGDB_DBBACKUP_NONINTERACTIVE:-0}" = "1" ]; then
    return 0
  fi
  ui_is_interactive || return 0
  return 1
}

_dbbackup_ui_pause_if() {
  local want_pause="${1:-1}"
  shift || true
  [ "$want_pause" = "1" ] || return 0
  _dbbackup_is_noninteractive && return 0
  ui_pause "${1:-按任意鍵返回...}"
}

_dbbackup_trim_ws() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

_dbbackup_ensure_dir_writable() {
  local dir="$1"
  [ -n "${dir:-}" ] || return 1

  if [ -e "$dir" ] && [ ! -d "$dir" ]; then
    tgdb_fail "目錄路徑不是資料夾：$dir" 1 || true
    return 1
  fi
  if [ ! -d "$dir" ]; then
    if ! mkdir -p "$dir" 2>/dev/null; then
      tgdb_fail "無法建立目錄：$dir（請確認權限）" 1 || true
      return 1
    fi
  fi
  if [ ! -w "$dir" ]; then
    tgdb_fail "目前使用者沒有寫入權限：$dir" 1 || true
    return 1
  fi
  return 0
}

_dbbackup_project_backup_dir() {
  local instance_dir="$1" db_type="$2"
  [ -n "${instance_dir:-}" ] || return 1
  [ -n "${db_type:-}" ] || return 1
  printf '%s\n' "${instance_dir%/}/${DBBACKUP_PROJECT_SUBDIR}/${db_type}"
}

_dbbackup_list_backups_newest_first() {
  local dir="$1" ext="$2"
  [ -d "$dir" ] || return 0
  [ -n "${ext:-}" ] || return 0
  ls -1t "$dir"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]."$ext" 2>/dev/null || true
}

_dbbackup_pick_existing_backup_file() {
  local dir="$1" ext="$2" __outvar="$3"
  [ -n "${__outvar:-}" ] || return 1

  local -a files=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && files+=("$line")
  done < <(_dbbackup_list_backups_newest_first "$dir" "$ext")

  if [ "${#files[@]}" -eq 0 ]; then
    tgdb_fail "尚未找到任何備份檔（$dir/*.${ext}）。" 1 || true
    _dbbackup_ui_pause_if 1 "按任意鍵返回..."
    return 1
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ 選擇要匯入的備份檔 ❖"
    echo "=================================="
    echo "目錄：$dir"
    echo "類型：*.${ext}"
    echo "----------------------------------"
    local i bn
    for i in "${!files[@]}"; do
      bn="$(basename "${files[$i]}")"
      printf "%2d. %s\n" "$((i + 1))" "$bn"
    done
    echo "----------------------------------"
    echo "0. 取消"
    echo "=================================="
    local choice
    read -r -e -p "請輸入選擇 [0-${#files[@]}]: " choice
    if [ "$choice" = "0" ]; then
      return 2
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
      printf -v "$__outvar" '%s' "${files[$((choice - 1))]}"
      return 0
    fi
    echo "無效選項，請重新輸入。"
    sleep 1
  done
}

_dbbackup_pause_on_error() {
  local rc="${1:-0}"
  [ "$rc" -eq 0 ] && return 0
  [ "$rc" -eq 2 ] && return 0
  _dbbackup_ui_pause_if 1 "按任意鍵返回..."
  return 0
}

_dbbackup_prune_old_backups() {
  local dir="$1" max_keep="${2:-$DBBACKUP_MAX_KEEP}" primary_ext="${3:-}"
  [ -d "$dir" ] || return 0
  [[ "${max_keep:-}" =~ ^[0-9]+$ ]] || max_keep="$(_dbbackup_max_keep_get)"
  [ "$max_keep" -gt 0 ] 2>/dev/null || max_keep="$(_dbbackup_max_keep_get)"
  primary_ext="$(_dbbackup_trim_ws "${primary_ext:-}")"

  # 以「主要備份檔」判斷保留數量，避免把同一份備份（dump/globals/meta）拆開刪。
  local glob_pat=""
  if [ -n "$primary_ext" ]; then
    glob_pat="$dir/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].${primary_ext}"
  else
    glob_pat="$dir/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].*"
  fi

  local -a primary_files=()
  # shellcheck disable=SC2086 # glob_pat 為受控 glob
  mapfile -t primary_files < <(ls -1t $glob_pat 2>/dev/null || true)
  if [ "${#primary_files[@]}" -le "$max_keep" ]; then
    return 0
  fi

  local i
  for ((i = max_keep; i < ${#primary_files[@]}; i++)); do
    local f ts
    f="${primary_files[$i]}"
    [ -f "$f" ] || continue
    ts="$(basename "$f")"
    ts="${ts%%.*}"
    rm -f -- "$dir/${ts}."* 2>/dev/null || true
  done

  return 0
}

_dbbackup_require_interactive() {
  if ! ui_is_interactive; then
    tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
  fi
  return 0
}

_dbbackup_unit_get_first_value() {
  local file="$1" key="$2"
  [ -n "$file" ] || return 1
  [ -n "$key" ] || return 1
  [ -f "$file" ] || return 1
  awk -F= -v k="$key" '
    $0 ~ "^[[:space:]]*" k "=" {
      sub("^[[:space:]]*" k "=", "", $0)
      print $0
      exit
    }
  ' "$file" 2>/dev/null
}

_dbbackup_unit_label_get_value() {
  local file="$1" want_key="$2"
  [ -f "$file" ] || return 1
  [ -n "${want_key:-}" ] || return 1

  awk -v k="$want_key" '
    /^[[:space:]]*Label[[:space:]]*=/ {
      line=$0
      sub(/^[[:space:]]*Label[[:space:]]*=[[:space:]]*/, "", line)
      sub(/[[:space:]]*(#.*)?$/, "", line)
      gsub(/^"|"$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

      n=split(line, parts, /[[:space:]]+/)
      for (i=1; i<=n; i++) {
        if (parts[i] ~ ("^" k "=")) {
          sub("^" k "=", "", parts[i])
          print parts[i]
          exit
        }
      }
    }
  ' "$file" 2>/dev/null
}

_dbbackup_unit_has_tgdb_db_label() {
  local file="$1" db_type="$2" # postgres|redis|mysql|mongo
  [ -f "$file" ] || return 1
  [ -n "${db_type:-}" ] || return 1
  awk -v want="tgdb_db=$db_type" '
    /^[[:space:]]*Label[[:space:]]*=/ {
      line=$0
      sub(/^[[:space:]]*Label[[:space:]]*=[[:space:]]*/, "", line)
      sub(/[[:space:]]*(#.*)?$/, "", line)
      gsub(/^"|"$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == want) { found=1; exit }
      if (index(line, want) > 0) { found=1; exit }
    }
    END{ if (found==1) exit 0; exit 1 }
  ' "$file" 2>/dev/null
}

_dbbackup_unit_volume_host_for_container_path() {
  local file="$1" container_path="$2"
  [ -n "$file" ] || return 1
  [ -n "$container_path" ] || return 1
  [ -f "$file" ] || return 1

  awk -F= -v cpath="$container_path" '
    $1=="Volume" {
      v=$2
      n=split(v, a, ":")
      if (n>=2 && a[2]==cpath) {
        print a[1]
        found=1
        exit
      }
    }
    END{ if (found==1) exit 0; exit 1 }
  ' "$file" 2>/dev/null
}

_dbbackup_find_db_endpoints() {
  local db_type="$1" # postgres|redis|mysql|mongo
  [ -n "$db_type" ] || return 1

  load_system_config >/dev/null 2>&1 || true

  local persist_dir
  persist_dir="$(rm_persist_config_dir 2>/dev/null || echo "")"

  local -A seen=()
  local file
  while IFS= read -r file; do
    [ -f "$file" ] || continue

    local container_name env_file instance_dir host_data_dir app_label display

    if [ "$db_type" = "mysql" ]; then
      if ! _dbbackup_unit_has_tgdb_db_label "$file" "mysql" && ! _dbbackup_unit_has_tgdb_db_label "$file" "mariadb"; then
        continue
      fi
    else
      _dbbackup_unit_has_tgdb_db_label "$file" "$db_type" || continue
    fi

    container_name="$(_dbbackup_unit_get_first_value "$file" "ContainerName" 2>/dev/null || true)"
    [ -n "${container_name:-}" ] || continue

    case "$db_type" in
      postgres) host_data_dir="$(_dbbackup_unit_volume_host_for_container_path "$file" "/var/lib/postgresql/data" 2>/dev/null || true)" ;;
      redis) host_data_dir="$(_dbbackup_unit_volume_host_for_container_path "$file" "/data" 2>/dev/null || true)" ;;
      mysql) host_data_dir="$(_dbbackup_unit_volume_host_for_container_path "$file" "/var/lib/mysql" 2>/dev/null || true)" ;;
      mongo) host_data_dir="$(_dbbackup_unit_volume_host_for_container_path "$file" "/data/db" 2>/dev/null || true)" ;;
      *) return 1 ;;
    esac

    [ -n "${host_data_dir:-}" ] || continue

    if [ "${seen[$container_name]+x}" = "x" ]; then
      continue
    fi
    seen["$container_name"]=1

    instance_dir="$(dirname "$host_data_dir" 2>/dev/null || echo "")"
    [ -n "${instance_dir:-}" ] || continue

    env_file="$instance_dir/.env"

    # 只列出有環境檔的目標（避免後續匯出/匯入缺少帳密）
    [ -f "$env_file" ] || continue

    app_label="$(_dbbackup_unit_label_get_value "$file" "app" 2>/dev/null || true)"
    if [ -n "${app_label:-}" ]; then
      display="${app_label} / ${container_name}"
    else
      display="$container_name"
    fi

    printf '%s|%s|%s|%s|%s\n' "$display" "$container_name" "$env_file" "$instance_dir" "$file"
  done < <(
    if declare -F rm_list_tgdb_runtime_quadlet_files_by_mode >/dev/null 2>&1; then
      rm_list_tgdb_runtime_quadlet_files_by_mode rootless 2>/dev/null | awk -F'\t' 'NF >= 4 && $3 ~ /\.container$/ { print $4 }'
    fi
    [ -n "${persist_dir:-}" ] && [ -d "$persist_dir" ] && find "$persist_dir" -type f -name "*.container" -print 2>/dev/null
  )
}

_dbbackup_pick_db_type() {
  local __outvar="$1"
  [ -n "${__outvar:-}" ] || return 1

  while true; do
    clear
    echo "=================================="
    echo "❖ 數據庫管理：匯入/匯出 ❖"
    echo "=================================="
    echo "請選擇資料庫類型："
    echo "----------------------------------"
    echo "1. PostgreSQL"
    echo "2. Redis"
    echo "3. MySQL / MariaDB"
    echo "4. MongoDB"
    echo "----------------------------------"
    echo "0. 取消"
    echo "=================================="
    local choice
    read -r -e -p "請輸入選擇 [0-4]: " choice
    case "$choice" in
      1) printf -v "$__outvar" '%s' "postgres"; return 0 ;;
      2) printf -v "$__outvar" '%s' "redis"; return 0 ;;
      3) printf -v "$__outvar" '%s' "mysql"; return 0 ;;
      4) printf -v "$__outvar" '%s' "mongo"; return 0 ;;
      0) return 2 ;;
      *) echo "無效選項，請重新輸入。"; sleep 1 ;;
    esac
  done
}

_dbbackup_pick_db_endpoint() {
  local db_type="$1" __outvar="$2"
  [ -n "$db_type" ] || return 1
  [ -n "${__outvar:-}" ] || return 1

  local -a endpoints=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && endpoints+=("$line")
  done < <(_dbbackup_find_db_endpoints "$db_type")

  if [ ${#endpoints[@]} -eq 0 ]; then
    if [ "$db_type" = "mysql" ]; then
      tgdb_fail "找不到可用的目標（MySQL / MariaDB）。請確認 DB 容器的 Quadlet 單元內有設定 Label=tgdb_db=mysql 或 tgdb_db=mariadb，且其資料卷掛載存在（/var/lib/mysql），並且同一實例資料夾內有 .env（用於讀取帳密）。" 1 || true
    else
      tgdb_fail "找不到可用的目標（$db_type）。請確認 DB 容器的 Quadlet 單元內有設定 Label=tgdb_db=${db_type}，且其資料卷掛載存在（Postgres: /var/lib/postgresql/data；Redis: /data；MongoDB: /data/db），並且同一實例資料夾內有 .env（用於讀取帳密）。" 1 || true
    fi
    ui_pause "按任意鍵返回..."
    return 1
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ 數據庫管理：選擇目標 ❖"
    echo "=================================="
    echo "類型：$db_type"
    echo "----------------------------------"
    local i display container_name env_file instance_dir _
    for i in "${!endpoints[@]}"; do
      IFS='|' read -r display container_name env_file instance_dir _ <<< "${endpoints[$i]}"
      printf '%2d. %s\n' "$((i + 1))" "$display"
      printf '    - 容器：%s\n' "$container_name"
      printf '    - 設定：%s\n' "$env_file"
    done
    echo "----------------------------------"
    echo "0. 取消"
    echo "=================================="
    local choice
    read -r -e -p "請輸入選擇 [0-${#endpoints[@]}]: " choice
    if [ "$choice" = "0" ]; then
      return 2
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#endpoints[@]} ]; then
      printf -v "$__outvar" '%s' "${endpoints[$((choice - 1))]}"
      return 0
    fi
    echo "無效選項，請重新輸入。"
    sleep 1
  done
}

_dbbackup_env_get_kv() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  [ -n "$key" ] || return 1
  # EnvironmentFile/.env：可能包含註解/空白；也可能出現 KEY = VALUE（等號兩側空白）。
  # 注意：不可直接改寫 $1，否則 awk 會用 OFS 重組 $0 造成前置空白（例如 " 321"）。
  awk -v k="$key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      line=$0
      sub(/\r$/, "", line)
      if (match(line, "^[[:space:]]*" k "[[:space:]]*=")) {
        sub("^[[:space:]]*" k "[[:space:]]*=", "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
          line=substr(line, 2, length(line)-2)
        }
        print line
        exit
      }
    }
  ' "$file" 2>/dev/null
}

_dbbackup_ensure_container_running() {
  local container_name="$1"
  [ -n "$container_name" ] || return 1

  if ! command -v podman >/dev/null 2>&1; then
    tgdb_fail "未偵測到 podman，無法執行此功能。" 1 || true
    return 1
  fi

  if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container_name"; then
    return 0
  fi

  if ! podman container exists "$container_name" 2>/dev/null; then
    tgdb_fail "找不到容器：$container_name（請先部署/啟動對應服務）。" 1 || true
    return 1
  fi

  # 非互動模式：不詢問，直接嘗試啟動一次
  if _dbbackup_is_noninteractive; then
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user start "${container_name}.service" 2>/dev/null || true
    fi
    podman start "$container_name" >/dev/null 2>&1 || true

    if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container_name"; then
      return 0
    fi

    tgdb_fail "容器未執行：$container_name（非互動模式無法詢問，請先手動啟動後再重試）。" 1 || true
    return 1
  fi

  tgdb_warn "容器未執行：$container_name"
  if ! ui_confirm_yn "是否嘗試啟動 $container_name？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    local rc=$?
    [ "$rc" -eq 2 ] && return 2
    return 1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user start "${container_name}.service" 2>/dev/null || true
  fi
  podman start "$container_name" >/dev/null 2>&1 || true

  if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container_name"; then
    return 0
  fi

  tgdb_fail "啟動失敗：$container_name（請先檢查單元/日誌）。" 1 || true
  return 1
}

_dbbackup_wait_postgres_ready() {
  local container_name="$1" user="$2" password="$3" timeout="${4:-$DBBACKUP_DB_READY_TIMEOUT}" interval="${5:-$DBBACKUP_DB_READY_INTERVAL}"
  [ -n "$container_name" ] || return 1
  [ -n "$user" ] || return 1
  [ -n "$password" ] || return 1
  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout="$DBBACKUP_DB_READY_TIMEOUT"
  [[ "$interval" =~ ^[0-9]+$ ]] || interval="$DBBACKUP_DB_READY_INTERVAL"
  [ "$timeout" -gt 0 ] || timeout="$DBBACKUP_DB_READY_TIMEOUT"
  [ "$interval" -gt 0 ] || interval="$DBBACKUP_DB_READY_INTERVAL"

  local waited=0 rc=0 last_out=""
  while [ "$waited" -lt "$timeout" ]; do
    last_out="$(podman exec -e TGDB_USER="$user" -e TGDB_PASS="$password" \
      "$container_name" sh -c 'set -eu; export PGPASSWORD="$TGDB_PASS"; psql -h 127.0.0.1 -p 5432 -U "$TGDB_USER" -d postgres -c "SELECT 1;" >/dev/null' 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    fi
    rc=0
    sleep "$interval"
    waited=$((waited + interval))
  done

  last_out="$(printf '%s' "$last_out" | head -n 1)"
  tgdb_fail "等待 PostgreSQL 就緒逾時（${timeout} 秒，容器：$container_name）：$last_out" 1 || true
  return 1
}

_dbbackup_wait_mysql_ready() {
  local container_name="$1" user="$2" password="$3" timeout="${4:-$DBBACKUP_DB_READY_TIMEOUT}" interval="${5:-$DBBACKUP_DB_READY_INTERVAL}"
  [ -n "$container_name" ] || return 1
  [ -n "$user" ] || return 1
  [ -n "$password" ] || return 1
  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout="$DBBACKUP_DB_READY_TIMEOUT"
  [[ "$interval" =~ ^[0-9]+$ ]] || interval="$DBBACKUP_DB_READY_INTERVAL"
  [ "$timeout" -gt 0 ] || timeout="$DBBACKUP_DB_READY_TIMEOUT"
  [ "$interval" -gt 0 ] || interval="$DBBACKUP_DB_READY_INTERVAL"

  local waited=0 rc=0 last_out=""
  while [ "$waited" -lt "$timeout" ]; do
    last_out="$(podman exec -e TGDB_USER="$user" -e TGDB_PASS="$password" \
      "$container_name" sh -c '
        set -eu
        export MYSQL_PWD="$TGDB_PASS"
        if command -v mysql >/dev/null 2>&1; then
          mysql -h 127.0.0.1 -P 3306 -u"$TGDB_USER" -e "SELECT 1;" >/dev/null
          exit 0
        fi
        if command -v mariadb >/dev/null 2>&1; then
          mariadb -h 127.0.0.1 -P 3306 -u"$TGDB_USER" -e "SELECT 1;" >/dev/null
          exit 0
        fi
        echo "找不到 mysql / mariadb 指令" >&2
        exit 1
      ' 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    fi
    rc=0
    sleep "$interval"
    waited=$((waited + interval))
  done

  last_out="$(printf '%s' "$last_out" | head -n 1)"
  tgdb_fail "等待 MySQL / MariaDB 就緒逾時（${timeout} 秒，容器：$container_name）：$last_out" 1 || true
  return 1
}
