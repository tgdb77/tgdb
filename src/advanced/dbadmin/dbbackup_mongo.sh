#!/bin/bash

# 數據庫備份：MongoDB 匯出/匯入
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_DBADMIN_DBBACKUP_MONGO_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_DBADMIN_DBBACKUP_MONGO_LOADED=1

DBBACKUP_MONGO_CONN_MODE=""
DBBACKUP_MONGO_URI=""
DBBACKUP_MONGO_URI_KEY=""
DBBACKUP_MONGO_DB=""
DBBACKUP_MONGO_USER=""
DBBACKUP_MONGO_PASS=""
DBBACKUP_MONGO_AUTH_DB=""
DBBACKUP_MONGO_AUTH_SOURCE=""

_dbbackup_mongo_reset_conn() {
  DBBACKUP_MONGO_CONN_MODE=""
  DBBACKUP_MONGO_URI=""
  DBBACKUP_MONGO_URI_KEY=""
  DBBACKUP_MONGO_DB=""
  DBBACKUP_MONGO_USER=""
  DBBACKUP_MONGO_PASS=""
  DBBACKUP_MONGO_AUTH_DB=""
  DBBACKUP_MONGO_AUTH_SOURCE=""
}

_dbbackup_mongo_uri_get_db_name() {
  local uri="$1"
  [ -n "${uri:-}" ] || return 1

  local rest path db
  rest="${uri#mongodb://}"
  rest="${rest#mongodb+srv://}"
  rest="${rest#*@}"
  case "$rest" in
    */*)
      path="${rest#*/}"
      path="${path%%\?*}"
      db="${path%%/*}"
      [ -n "${db:-}" ] || return 1
      printf '%s\n' "$db"
      return 0
      ;;
  esac

  return 1
}

_dbbackup_mongo_uri_get_query_value() {
  local uri="$1" want_key="$2"
  [ -n "${uri:-}" ] || return 1
  [ -n "${want_key:-}" ] || return 1

  local query pair key value OLDIFS
  query="${uri#*\?}"
  [ "$query" != "$uri" ] || return 1

  OLDIFS="$IFS"
  IFS='&'
  for pair in $query; do
    key="${pair%%=*}"
    value="${pair#*=}"
    if [ "$key" = "$want_key" ]; then
      IFS="$OLDIFS"
      printf '%s\n' "$value"
      return 0
    fi
  done
  IFS="$OLDIFS"

  return 1
}

_dbbackup_mongo_resolve_connection() {
  local env_file="$1"
  [ -f "$env_file" ] || return 1

  _dbbackup_mongo_reset_conn

  local key val
  for key in MONGODB_URI MONGO_URL MONGO_URI DATABASE_URL ACKEE_MONGODB; do
    val="$(_dbbackup_env_get_kv "$env_file" "$key" 2>/dev/null || true)"
    if [ -n "${val:-}" ]; then
      DBBACKUP_MONGO_CONN_MODE="uri"
      DBBACKUP_MONGO_URI="$val"
      DBBACKUP_MONGO_URI_KEY="$key"
      break
    fi
  done

  DBBACKUP_MONGO_DB="$(_dbbackup_env_get_kv "$env_file" "MONGO_INITDB_DATABASE" 2>/dev/null || true)"
  [ -n "${DBBACKUP_MONGO_DB:-}" ] || DBBACKUP_MONGO_DB="$(_dbbackup_env_get_kv "$env_file" "MONGO_DATABASE" 2>/dev/null || true)"
  [ -n "${DBBACKUP_MONGO_DB:-}" ] || DBBACKUP_MONGO_DB="$(_dbbackup_env_get_kv "$env_file" "MONGODB_DATABASE" 2>/dev/null || true)"

  DBBACKUP_MONGO_AUTH_DB="$(_dbbackup_env_get_kv "$env_file" "MONGO_AUTH_SOURCE" 2>/dev/null || true)"
  [ -n "${DBBACKUP_MONGO_AUTH_DB:-}" ] || DBBACKUP_MONGO_AUTH_DB="$(_dbbackup_env_get_kv "$env_file" "MONGODB_AUTH_SOURCE" 2>/dev/null || true)"

  if [ "$DBBACKUP_MONGO_CONN_MODE" = "uri" ]; then
    [ -n "${DBBACKUP_MONGO_DB:-}" ] || DBBACKUP_MONGO_DB="$(_dbbackup_mongo_uri_get_db_name "$DBBACKUP_MONGO_URI" 2>/dev/null || true)"
    [ -n "${DBBACKUP_MONGO_AUTH_DB:-}" ] || DBBACKUP_MONGO_AUTH_DB="$(_dbbackup_mongo_uri_get_query_value "$DBBACKUP_MONGO_URI" "authSource" 2>/dev/null || true)"
    DBBACKUP_MONGO_AUTH_SOURCE="uri:${DBBACKUP_MONGO_URI_KEY}"
  else
    DBBACKUP_MONGO_CONN_MODE="direct"
    DBBACKUP_MONGO_USER="$(_dbbackup_env_get_kv "$env_file" "MONGO_INITDB_ROOT_USERNAME" 2>/dev/null || true)"
    DBBACKUP_MONGO_PASS="$(_dbbackup_env_get_kv "$env_file" "MONGO_INITDB_ROOT_PASSWORD" 2>/dev/null || true)"
    if [ -n "${DBBACKUP_MONGO_USER:-}" ] || [ -n "${DBBACKUP_MONGO_PASS:-}" ]; then
      DBBACKUP_MONGO_AUTH_SOURCE="MONGO_INITDB_ROOT_USERNAME/MONGO_INITDB_ROOT_PASSWORD"
      [ -n "${DBBACKUP_MONGO_AUTH_DB:-}" ] || DBBACKUP_MONGO_AUTH_DB="admin"
    else
      DBBACKUP_MONGO_USER="$(_dbbackup_env_get_kv "$env_file" "MONGO_USERNAME" 2>/dev/null || true)"
      DBBACKUP_MONGO_PASS="$(_dbbackup_env_get_kv "$env_file" "MONGO_PASSWORD" 2>/dev/null || true)"
      [ -n "${DBBACKUP_MONGO_USER:-}" ] || DBBACKUP_MONGO_USER="$(_dbbackup_env_get_kv "$env_file" "MONGODB_USERNAME" 2>/dev/null || true)"
      [ -n "${DBBACKUP_MONGO_PASS:-}" ] || DBBACKUP_MONGO_PASS="$(_dbbackup_env_get_kv "$env_file" "MONGODB_PASSWORD" 2>/dev/null || true)"
      if [ -n "${DBBACKUP_MONGO_USER:-}" ] || [ -n "${DBBACKUP_MONGO_PASS:-}" ]; then
        DBBACKUP_MONGO_AUTH_SOURCE="MONGO_USERNAME/MONGO_PASSWORD"
        [ -n "${DBBACKUP_MONGO_AUTH_DB:-}" ] || DBBACKUP_MONGO_AUTH_DB="${DBBACKUP_MONGO_DB:-admin}"
      else
        DBBACKUP_MONGO_AUTH_SOURCE="noauth"
      fi
    fi
  fi

  if [ -n "${DBBACKUP_MONGO_USER:-}" ] && [ -z "${DBBACKUP_MONGO_PASS:-}" ]; then
    tgdb_fail "MongoDB 連線資訊不完整：找到帳號但缺少密碼（$env_file）。" 1 || true
    return 1
  fi
  if [ -z "${DBBACKUP_MONGO_USER:-}" ] && [ -n "${DBBACKUP_MONGO_PASS:-}" ]; then
    tgdb_fail "MongoDB 連線資訊不完整：找到密碼但缺少帳號（$env_file）。" 1 || true
    return 1
  fi

  if [ -z "${DBBACKUP_MONGO_DB:-}" ]; then
    tgdb_fail "找不到 MongoDB 目標資料庫名稱：$env_file（支援 MONGODB_URI / MONGO_URL / ACKEE_MONGODB / MONGO_INITDB_DATABASE 等）。" 1 || true
    return 1
  fi

  return 0
}

_dbbackup_wait_mongo_ready() {
  local container_name="$1" timeout="${2:-$DBBACKUP_DB_READY_TIMEOUT}" interval="${3:-$DBBACKUP_DB_READY_INTERVAL}"
  [ -n "$container_name" ] || return 1
  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout="$DBBACKUP_DB_READY_TIMEOUT"
  [[ "$interval" =~ ^[0-9]+$ ]] || interval="$DBBACKUP_DB_READY_INTERVAL"
  [ "$timeout" -gt 0 ] || timeout="$DBBACKUP_DB_READY_TIMEOUT"
  [ "$interval" -gt 0 ] || interval="$DBBACKUP_DB_READY_INTERVAL"

  local waited=0 rc=0 last_out=""
  while [ "$waited" -lt "$timeout" ]; do
    last_out="$(podman exec \
      -e TGDB_URI="$DBBACKUP_MONGO_URI" \
      -e TGDB_USER="$DBBACKUP_MONGO_USER" \
      -e TGDB_PASS="$DBBACKUP_MONGO_PASS" \
      -e TGDB_AUTH_DB="$DBBACKUP_MONGO_AUTH_DB" \
      "$container_name" sh -c '
        set -eu
        if [ -n "${TGDB_URI:-}" ]; then
          mongosh "$TGDB_URI" --quiet --eval "db.adminCommand({ ping: 1 })" >/dev/null
          exit 0
        fi

        set -- mongosh --quiet --host 127.0.0.1 --port 27017
        if [ -n "${TGDB_USER:-}" ]; then
          set -- "$@" --username "$TGDB_USER" --password "$TGDB_PASS"
          if [ -n "${TGDB_AUTH_DB:-}" ]; then
            set -- "$@" --authenticationDatabase "$TGDB_AUTH_DB"
          fi
        fi
        set -- "$@" --eval "db.adminCommand({ ping: 1 })"
        "$@" >/dev/null
      ' 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    fi
    rc=0
    sleep "$interval"
    waited=$((waited + interval))
  done

  last_out="$(printf '%s' "$last_out" | head -n 1)"
  tgdb_fail "等待 MongoDB 就緒逾時（${timeout} 秒，容器：$container_name）：$last_out" 1 || true
  return 1
}

_dbbackup_mongo_export() {
  local container_name="$1" env_file="$2" instance_dir="$3" want_pause="${4:-1}"
  [ -n "$container_name" ] || return 1
  [ -f "$env_file" ] || return 1
  [ -n "${instance_dir:-}" ] || instance_dir="$(dirname "$env_file" 2>/dev/null || echo "")"

  _dbbackup_ensure_container_running "$container_name" || {
    local rc=$?
    _dbbackup_pause_on_error "$rc" || true
    return "$rc"
  }

  if ! podman exec "$container_name" sh -c 'command -v mongodump >/dev/null 2>&1 && command -v mongosh >/dev/null 2>&1' 2>/dev/null; then
    tgdb_fail "容器內缺少 mongodump/mongosh：$container_name（此功能暫不支援該映像）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  _dbbackup_mongo_resolve_connection "$env_file" || {
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  }

  echo "⏳ 等待 MongoDB 服務就緒（最多 ${DBBACKUP_DB_READY_TIMEOUT} 秒）..."
  if ! _dbbackup_wait_mongo_ready "$container_name"; then
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local out_dir ts out_archive out_meta
  out_dir="$(_dbbackup_project_backup_dir "$instance_dir" "mongo")" || return 1
  _dbbackup_ensure_dir_writable "$out_dir" || { _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."; return 1; }
  chmod 700 "$out_dir" 2>/dev/null || true
  echo "輸出目錄：$out_dir"
  echo "目標資料庫：$DBBACKUP_MONGO_DB"
  echo "連線來源：$DBBACKUP_MONGO_AUTH_SOURCE"
  echo "設定檔：$env_file"

  ts="$(date +%Y%m%d-%H%M%S)"
  out_archive="$out_dir/${ts}.archive.gz"
  out_meta="$out_dir/${ts}.meta.conf"

  local tmp_archive="/tmp/tgdb_${ts}.archive.gz"
  local dump_out="" dump_rc=0
  dump_out="$(podman exec \
    -e TGDB_URI="$DBBACKUP_MONGO_URI" \
    -e TGDB_DB="$DBBACKUP_MONGO_DB" \
    -e TGDB_USER="$DBBACKUP_MONGO_USER" \
    -e TGDB_PASS="$DBBACKUP_MONGO_PASS" \
    -e TGDB_AUTH_DB="$DBBACKUP_MONGO_AUTH_DB" \
    -e TGDB_OUT="$tmp_archive" \
    "$container_name" sh -c '
      set -eu
      set -- mongodump --archive="$TGDB_OUT" --gzip
      if [ -n "${TGDB_URI:-}" ]; then
        set -- "$@" --uri "$TGDB_URI"
      else
        set -- "$@" --host 127.0.0.1 --port 27017
        if [ -n "${TGDB_USER:-}" ]; then
          set -- "$@" --username "$TGDB_USER" --password "$TGDB_PASS"
          if [ -n "${TGDB_AUTH_DB:-}" ]; then
            set -- "$@" --authenticationDatabase "$TGDB_AUTH_DB"
          fi
        fi
      fi
      set -- "$@" --db "$TGDB_DB"
      "$@"
    ' 2>&1)" || dump_rc=$?
  if [ "$dump_rc" -ne 0 ]; then
    tgdb_fail "匯出失敗：$container_name（$dump_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local cp_out="" cp_rc=0
  local tmp_out_archive="${out_archive}.tmp"
  rm -f -- "$tmp_out_archive" 2>/dev/null || true
  cp_out="$(podman cp "${container_name}:${tmp_archive}" "$tmp_out_archive" 2>&1)" || cp_rc=$?
  if [ "$cp_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_archive" >/dev/null 2>&1 || true
    tgdb_fail "無法從容器取回檔案：$container_name:$tmp_archive（$cp_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi
  podman exec "$container_name" rm -f "$tmp_archive" >/dev/null 2>&1 || true
  if ! mv -f -- "$tmp_out_archive" "$out_archive" 2>/dev/null; then
    rm -f -- "$tmp_out_archive" 2>/dev/null || true
    tgdb_fail "匯出檔案寫入失敗（無法原子改名）：$tmp_out_archive -> $out_archive" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  {
    echo "created_at=$ts"
    echo "db_type=mongo"
    echo "container_name=$container_name"
    echo "env_file=$env_file"
    echo "db_name=$DBBACKUP_MONGO_DB"
    echo "auth_source=$DBBACKUP_MONGO_AUTH_SOURCE"
    echo "auth_db=$DBBACKUP_MONGO_AUTH_DB"
    echo "uri_key=$DBBACKUP_MONGO_URI_KEY"
    echo "format=mongodump_archive_gzip"
  } >"$out_meta" 2>/dev/null || true
  chmod 600 "$out_meta" 2>/dev/null || true

  _dbbackup_prune_old_backups "$out_dir" "$(_dbbackup_max_keep_get)" "archive.gz" || true

  echo "✅ 匯出完成：$out_archive"
  echo " - meta：$out_meta"
  _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
  return 0
}

_dbbackup_mongo_import_overwrite() {
  local container_name="$1" env_file="$2" instance_dir="$3" want_pause="${4:-1}" forced_archive_path="${5:-}" assume_yes="${6:-0}"
  [ -n "$container_name" ] || return 1
  [ -f "$env_file" ] || return 1
  [ -n "${instance_dir:-}" ] || instance_dir="$(dirname "$env_file" 2>/dev/null || echo "")"

  _dbbackup_ensure_container_running "$container_name" || {
    local rc=$?
    _dbbackup_pause_on_error "$rc" || true
    return "$rc"
  }

  if ! podman exec "$container_name" sh -c 'command -v mongorestore >/dev/null 2>&1 && command -v mongosh >/dev/null 2>&1' 2>/dev/null; then
    tgdb_fail "容器內缺少 mongorestore/mongosh：$container_name（此功能暫不支援該映像）。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local archive_dir archive_path
  archive_dir="$(_dbbackup_project_backup_dir "$instance_dir" "mongo")" || return 1
  forced_archive_path="$(_dbbackup_trim_ws "${forced_archive_path:-}")"
  if [ -n "${forced_archive_path:-}" ]; then
    archive_path="$forced_archive_path"
    if [ ! -f "$archive_path" ]; then
      tgdb_fail "找不到備份檔：$archive_path" 1 || true
      _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
      return 1
    fi
  else
    _dbbackup_pick_existing_backup_file "$archive_dir" "archive.gz" archive_path || return $?
  fi

  _dbbackup_mongo_resolve_connection "$env_file" || {
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  }

  if [[ ! "$DBBACKUP_MONGO_DB" =~ ^[A-Za-z0-9._-]+$ ]]; then
    tgdb_fail "偵測到 MongoDB 名稱含特殊字元（db=$DBBACKUP_MONGO_DB）。此功能暫不支援自動覆蓋，請改用手動還原。" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  echo "⚠️ 重要提醒：此操作會『覆蓋』目標 MongoDB 資料庫內容。"
  echo " - 目標容器：$container_name"
  echo " - 目標資料庫：$DBBACKUP_MONGO_DB"
  echo " - 連線來源：$DBBACKUP_MONGO_AUTH_SOURCE"
  echo " - 匯入檔案：$archive_path"
  echo "建議：先停止所有會連線到此 DB 的上游服務，避免匯入期間被寫入。"

  if [ "${assume_yes:-0}" != "1" ]; then
    if ! ui_confirm_yn "確認繼續覆蓋還原嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
      local rc=$?
      [ "$rc" -eq 2 ] && return 2
      return 0
    fi
  fi

  echo "⏳ 等待 MongoDB 服務就緒（最多 ${DBBACKUP_DB_READY_TIMEOUT} 秒）..."
  if ! _dbbackup_wait_mongo_ready "$container_name"; then
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local ts tmp_archive
  ts="$(date +%Y%m%d-%H%M%S)"
  tmp_archive="/tmp/tgdb_import_${ts}.archive.gz"
  local cp_out="" cp_rc=0
  cp_out="$(podman cp "$archive_path" "${container_name}:${tmp_archive}" 2>&1)" || cp_rc=$?
  if [ "$cp_rc" -ne 0 ]; then
    tgdb_fail "無法把檔案複製進容器：$container_name（$cp_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local drop_out="" drop_rc=0
  drop_out="$(podman exec \
    -e TGDB_URI="$DBBACKUP_MONGO_URI" \
    -e TGDB_DB="$DBBACKUP_MONGO_DB" \
    -e TGDB_USER="$DBBACKUP_MONGO_USER" \
    -e TGDB_PASS="$DBBACKUP_MONGO_PASS" \
    -e TGDB_AUTH_DB="$DBBACKUP_MONGO_AUTH_DB" \
    "$container_name" sh -c '
      set -eu
      if [ -n "${TGDB_URI:-}" ]; then
        mongosh "$TGDB_URI" --quiet --eval "db.getSiblingDB(\"$TGDB_DB\").dropDatabase()" >/dev/null
        exit 0
      fi

      set -- mongosh --quiet --host 127.0.0.1 --port 27017
      if [ -n "${TGDB_USER:-}" ]; then
        set -- "$@" --username "$TGDB_USER" --password "$TGDB_PASS"
        if [ -n "${TGDB_AUTH_DB:-}" ]; then
          set -- "$@" --authenticationDatabase "$TGDB_AUTH_DB"
        fi
      fi
      set -- "$@" --eval "db.getSiblingDB(\"$TGDB_DB\").dropDatabase()"
      "$@" >/dev/null
    ' 2>&1)" || drop_rc=$?
  if [ "$drop_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_archive" >/dev/null 2>&1 || true
    tgdb_fail "清空資料庫失敗：$DBBACKUP_MONGO_DB（$drop_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  local restore_out="" restore_rc=0
  restore_out="$(podman exec \
    -e TGDB_URI="$DBBACKUP_MONGO_URI" \
    -e TGDB_DB="$DBBACKUP_MONGO_DB" \
    -e TGDB_USER="$DBBACKUP_MONGO_USER" \
    -e TGDB_PASS="$DBBACKUP_MONGO_PASS" \
    -e TGDB_AUTH_DB="$DBBACKUP_MONGO_AUTH_DB" \
    -e TGDB_FILE="$tmp_archive" \
    "$container_name" sh -c '
      set -eu
      set -- mongorestore --archive="$TGDB_FILE" --gzip --drop --nsInclude "$TGDB_DB.*"
      if [ -n "${TGDB_URI:-}" ]; then
        set -- "$@" --uri "$TGDB_URI"
      else
        set -- "$@" --host 127.0.0.1 --port 27017
        if [ -n "${TGDB_USER:-}" ]; then
          set -- "$@" --username "$TGDB_USER" --password "$TGDB_PASS"
          if [ -n "${TGDB_AUTH_DB:-}" ]; then
            set -- "$@" --authenticationDatabase "$TGDB_AUTH_DB"
          fi
        fi
      fi
      "$@"
    ' 2>&1)" || restore_rc=$?
  if [ "$restore_rc" -ne 0 ]; then
    podman exec "$container_name" rm -f "$tmp_archive" >/dev/null 2>&1 || true
    tgdb_fail "匯入失敗：$container_name（$restore_out）" 1 || true
    _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
    return 1
  fi

  podman exec "$container_name" rm -f "$tmp_archive" >/dev/null 2>&1 || true

  if _dbbackup_wait_mongo_ready "$container_name" 30 2; then
    echo "✅ 匯入完成：已覆蓋還原 $DBBACKUP_MONGO_DB"
  else
    tgdb_warn "匯入完成，但匯入後就緒檢查未通過，請手動確認容器日誌與資料完整性。"
  fi

  echo "ℹ️ 建議：啟動上游服務前先做基本查詢/健康檢查確認資料完整。"
  _dbbackup_ui_pause_if "$want_pause" "按任意鍵返回..."
  return 0
}
