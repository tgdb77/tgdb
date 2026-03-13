#!/bin/bash

# TGDB AppSpec 執行器：基礎工具/共用函式
# 注意：
# - 本檔案為 library，會被 src/apps/app_spec_exec.sh source
# - 請勿在此更改 shell options（例如 set -euo pipefail）。

declare -Ag TGDB_APPSPEC_CTX=()

_appspec_rel_path_is_safe() {
  local p="$1"
  [ -n "${p:-}" ] || return 1
  case "$p" in
    /*|*\\*|*..*) return 1 ;;
  esac
  return 0
}

_appspec_join_service_path() {
  local service="$1" rel="$2"
  if ! _appspec_rel_path_is_safe "$rel"; then
    tgdb_fail "AppSpec 路徑不合法（$service）：$rel" 1 || true
    return 1
  fi
  printf '%s\n' "$CONFIG_DIR/$service/$rel"
}

_appspec_instance_rel_path_is_safe() {
  local p="$1"
  [ -n "${p:-}" ] || return 1
  case "$p" in
    /*|*\\*|*..*) return 1 ;;
  esac
  return 0
}

_appspec_truthy() {
  local v="${1:-}"
  case "${v,,}" in
    1|true|yes|y) return 0 ;;
  esac
  return 1
}

_appspec_trim_ws() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

_appspec_awk_regex_escape() {
  # 用於 awk regex（match_pattern），將常見 regex 特殊字元跳脫。
  local s="$1"
  local out="" ch
  local i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in
      "\\"|"."|"^"|"$"|"|"|"("|")"|"["|"]"|"{"|"}"|"*"|"+"|"?")
        out+="\\$ch"
        ;;
      *)
        out+="$ch"
        ;;
    esac
  done
  printf '%s' "$out"
}

_appspec_ctx_key() {
  local service="$1" name="$2" key="$3"
  printf '%s\n' "${service}:${name}:${key}"
}

_appspec_ctx_has() {
  local service="$1" name="$2" key="$3"
  local k
  k="$(_appspec_ctx_key "$service" "$name" "$key")"
  [ -n "${TGDB_APPSPEC_CTX[$k]+x}" ]
}

_appspec_ctx_get() {
  local service="$1" name="$2" key="$3" default="${4:-}"
  local k
  k="$(_appspec_ctx_key "$service" "$name" "$key")"
  if [ -n "${TGDB_APPSPEC_CTX[$k]+x}" ]; then
    printf '%s\n' "${TGDB_APPSPEC_CTX[$k]}"
    return 0
  fi
  printf '%s\n' "$default"
}

_appspec_ctx_set() {
  local service="$1" name="$2" key="$3" value="$4"
  local k
  k="$(_appspec_ctx_key "$service" "$name" "$key")"
  TGDB_APPSPEC_CTX["$k"]="$value"
}

_appspec_export_env() {
  local env_key="$1" value="$2"
  [ -n "${env_key:-}" ] || return 0
  if declare -F _env_key_is_valid >/dev/null 2>&1; then
    _env_key_is_valid "$env_key" || return 1
  else
    [[ "$env_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  fi
  printf -v "$env_key" '%s' "$value"
  # shellcheck disable=SC2163 # env_key 為動態環境變數名稱
  export "$env_key"
  return 0
}

_appspec_parse_pipe_def() {
  local def="$1" out_name_var="$2"
  local -n out_opts_ref="$3"

  out_opts_ref=()

  local -a parts=()
  IFS='|' read -r -a parts <<< "$def"

  local name
  name="$(_appspec_trim_ws "${parts[0]-}")"
  printf -v "$out_name_var" '%s' "$name"

  local i seg k v
  for ((i = 1; i < ${#parts[@]}; i++)); do
    seg="$(_appspec_trim_ws "${parts[$i]}")"
    [ -z "$seg" ] && continue
    case "$seg" in
      *=*)
        k="$(_appspec_trim_ws "${seg%%=*}")"
        v="$(_appspec_trim_ws "${seg#*=}")"
        ;;
      *)
        k="$seg"
        v="1"
        ;;
    esac
    [ -z "$k" ] && continue
    if [[ ! "$k" =~ ^[A-Za-z0-9_]+$ ]]; then
      tgdb_warn "忽略無效 AppSpec 參數鍵：$k"
      continue
    fi
    # shellcheck disable=SC2034 # out_opts_ref 透過 nameref 回傳（shellcheck 誤判）
    out_opts_ref["$k"]="$v"
  done

  return 0
}

_appspec_build_render_kv_args() {
  local -n out_ref="$1"
  local service="$2" name="$3"

  out_ref=()
  local prefix="${service}:${name}:"

  local full key value
  for full in "${!TGDB_APPSPEC_CTX[@]}"; do
    case "$full" in
      "${prefix}"*)
        key="${full#"$prefix"}"
        value="${TGDB_APPSPEC_CTX[$full]}"
        case "$key" in
          container_name|host_port|instance_dir|TGDB_DIR|volume_dir|user_id|group_id|user_name|pass_word)
            continue
            ;;
        esac
        if declare -F _env_key_is_valid >/dev/null 2>&1; then
          _env_key_is_valid "$key" || continue
        else
          [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        fi
        out_ref+=("${key}=${value}")
        ;;
    esac
  done
}

_appspec_maybe_enable_podman_socket() {
  local service="$1"

  local v
  v="$(appspec_get "$service" "require_podman_socket" "0")"
  _appspec_truthy "$v" || return 0

  if ! command -v systemctl >/dev/null 2>&1; then
    tgdb_warn "系統未提供 systemctl，無法自動啟用 Podman Socket（podman.sock）。"
    return 0
  fi

  if declare -F _systemctl_user_try >/dev/null 2>&1; then
    if _systemctl_user_try is-active -- podman.socket >/dev/null 2>&1; then
      return 0
    fi
    echo "正在為目前使用者啟用 Podman Socket（podman.sock）..." >&2
    if ! _systemctl_user_try enable --now -- podman.socket >/dev/null 2>&1; then
      tgdb_warn "無法啟用 Podman Socket，請確認已安裝 Podman 並支援 systemd --user。"
    fi
    return 0
  fi

  if systemctl --user is-active --quiet podman.socket 2>/dev/null; then
    return 0
  fi
  echo "正在為目前使用者啟用 Podman Socket（podman.sock）..." >&2
  if ! systemctl --user enable --now podman.socket >/dev/null 2>&1; then
    tgdb_warn "無法啟用 Podman Socket，請確認已安裝 Podman 並支援 systemd --user。"
  fi
  return 0
}
