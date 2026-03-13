#!/bin/bash

# Apps：Quadlet 產生/模板渲染（由 src/apps-p.sh 載入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_app_extract_primary_host_port_from_unit_content() {
  local unit_content="$1"
  local publish=""

  publish="$(printf '%s\n' "$unit_content" | awk -F= '/^PublishPort=/{print $2; exit}' 2>/dev/null || true)"
  publish="${publish%%#*}"
  publish="${publish%% *}"
  publish="${publish//$'\t'/}"
  publish="${publish//$'\r'/}"

  if [ -z "${publish:-}" ]; then
    return 1
  fi

  # PublishPort 可能為：
  # - 127.0.0.1:<host>:<container>
  # - 0.0.0.0:<host>:<container>
  # - <host>:<container>
  if [[ "$publish" =~ ^(127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\]|::1):([0-9]+): ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "$publish" =~ ^([0-9]+): ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

_read_template() {
  local path="$1"
  if [ ! -f "$path" ]; then
    tgdb_fail "找不到模板：$path" 1 || return $?
  fi
  cat "$path"
}

_bash_replacement_escape() {
  local out_var="$1"
  local s="$2"
  # Bash 的 ${var//pattern/repl} 中，repl 內的 & 會被視為「匹配到的字串」。
  # 為避免密碼等內容含有 & 或 \ 時被誤解讀，需要先做跳脫。
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  printf -v "$out_var" '%s' "$s"
}

_render_quadlet_template() {
  local tpl="$1" name="$2" host_port="$3" instance_dir="$4" volume_dir="${5:-}" user_name="${6:-}" pass_word="${7:-}"
  shift 7 || true

  local content
  content=$(_read_template "$tpl") || return 1

  local tgdb_abs="$TGDB_DIR"
  local tgdb_name
  tgdb_name="$(basename "$TGDB_DIR" 2>/dev/null || echo "app")"
  local backup_root
  if declare -F tgdb_backup_root >/dev/null 2>&1; then
    backup_root="$(tgdb_backup_root)"
  else
    backup_root="${TGDB_BACKUP_ROOT:-$(dirname "${TGDB_DIR:-$HOME/.tgdb/app}")}"
  fi
  local user_id
  local group_id
  if declare -F _detect_invoking_uid >/dev/null 2>&1; then
    user_id="$(_detect_invoking_uid)"
  else
    user_id="$(id -u 2>/dev/null || echo "")"
  fi
  if declare -F _detect_invoking_gid >/dev/null 2>&1; then
    group_id="$(_detect_invoking_gid)"
  else
    group_id="$(id -g 2>/dev/null || echo "")"
  fi

  local -a keys=(
    "container_name"
    "host_port"
    "instance_dir"
    "TGDB_DIR"
    "tgdb_name"
    "backup_root"
    "volume_dir"
    "user_id"
    "group_id"
    "user_name"
    "pass_word"
  )
  local -a values=(
    "$name"
    "$host_port"
    "$instance_dir"
    "$tgdb_abs"
    "$tgdb_name"
    "$backup_root"
    "$volume_dir"
    "$user_id"
    "$group_id"
    "$user_name"
    "$pass_word"
  )

  declare -A key_index=(
    ["container_name"]=0
    ["host_port"]=1
    ["instance_dir"]=2
    ["TGDB_DIR"]=3
    ["tgdb_name"]=4
    ["backup_root"]=5
    ["volume_dir"]=6
    ["user_id"]=7
    ["group_id"]=8
    ["user_name"]=9
    ["pass_word"]=10
  )

  # 允許 app 額外提供 KEY=VALUE 形式的變數（僅替換已提供的 KEY）
  local kv key value idx
  for kv in "$@"; do
    case "$kv" in
      *=*)
        key="${kv%%=*}"
        value="${kv#*=}"
        [ -z "$key" ] && continue
        if ! _env_key_is_valid "$key"; then
          tgdb_warn "忽略無效模板變數鍵：$key"
          continue
        fi
        if [ "${key_index[$key]+x}" = "x" ]; then
          idx="${key_index[$key]}"
          values[idx]="$value"
        else
          key_index["$key"]="${#keys[@]}"
          keys+=("$key")
          values+=("$value")
        fi
        ;;
    esac
  done

  for idx in "${!keys[@]}"; do
    key="${keys[$idx]}"
    if ! _env_key_is_valid "$key"; then
      continue
    fi
    local repl
    _bash_replacement_escape repl "${values[$idx]}"
    content="${content//\$\{$key\}/$repl}"
  done

  # 輕量檢查：若仍殘留 ${KEY}，通常表示模板新增了佔位符但忘了傳入 KEY=VALUE
  local tmp="$content" token leftover_key
  local -a leftover_keys=()
  declare -A leftover_seen=()
  while [[ "$tmp" =~ (\$\{[A-Za-z_][A-Za-z0-9_]*\}) ]]; do
    token="${BASH_REMATCH[1]}"
    leftover_key="${token:2:${#token}-3}"
    if [ "${leftover_seen[$leftover_key]+x}" != "x" ]; then
      leftover_seen["$leftover_key"]=1
      leftover_keys+=("$leftover_key")
      [ "${#leftover_keys[@]}" -ge 10 ] && break
    fi
    tmp="${tmp#*"${token}"}"
  done
  if [ "${#leftover_keys[@]}" -gt 0 ]; then
    tgdb_warn "模板仍包含未替換的變數：${leftover_keys[*]}（請確認是否需要在 app 內傳入 KEY=VALUE）"
  fi

  printf '%s' "$content"
}
