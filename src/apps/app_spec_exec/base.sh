#!/bin/bash

# TGDB AppSpec 執行器：基礎工具/共用函式
# 注意：
# - 本檔案為 library，會被 src/apps/app_spec_exec.sh source
# - 請勿在此更改 shell options（例如 set -euo pipefail）。

declare -Ag TGDB_APPSPEC_CTX=()

_appspec_path_is_safe() {
  local p="$1"
  [ -n "${p:-}" ] || return 1
  case "$p" in
    /*|*\\*|*..*) return 1 ;;
  esac
  return 0
}

_appspec_rel_path_is_safe() {
  _appspec_path_is_safe "$1"
}

_appspec_join_service_path() {
  local service="$1" rel="$2"
  if ! _appspec_path_is_safe "$rel"; then
    tgdb_fail "AppSpec 路徑不合法（$service）：$rel" 1 || true
    return 1
  fi
  printf '%s\n' "$CONFIG_DIR/$service/$rel"
}

_appspec_instance_rel_path_is_safe() {
  _appspec_path_is_safe "$1"
}

_appspec_env_key_is_valid() {
  local env_key="$1"
  [ -n "${env_key:-}" ] || return 1
  if declare -F _env_key_is_valid >/dev/null 2>&1; then
    _env_key_is_valid "$env_key"
    return $?
  fi
  [[ "$env_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
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
  _appspec_env_key_is_valid "$env_key" || return 1
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
        _appspec_env_key_is_valid "$key" || continue
        out_ref+=("${key}=${value}")
        ;;
    esac
  done
}

_appspec_podman_sock_host_path() {
  local service="$1"
  local override
  override="$(appspec_get "$service" "podman_api_socket_path" "")"
  if [ -n "$override" ]; then
    printf '%s\n' "$override"
    return 0
  fi

  local deploy_mode
  deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"
  case "$deploy_mode" in
    rootful)
      printf '%s\n' "/run/podman/podman.sock"
      ;;
    *)
      local uid
      if declare -F _detect_invoking_uid >/dev/null 2>&1; then
        uid="$(_detect_invoking_uid)"
      else
        uid="$(id -u 2>/dev/null || echo "")"
      fi
      printf '%s\n' "/run/user/${uid}/podman/podman.sock"
      ;;
  esac
}

_appspec_maybe_enable_podman_socket() {
  local service="$1"
  local scope
  scope="$(_apps_current_scope 2>/dev/null || printf '%s\n' "user")"

  local v
  v="$(appspec_get "$service" "require_podman_socket" "0")"
  _appspec_truthy "$v" || return 0

  if ! command -v systemctl >/dev/null 2>&1; then
    tgdb_warn "系統未提供 systemctl，無法自動啟用 Podman Socket（podman.sock）。"
    return 0
  fi

  if declare -F tgdb_systemctl_try >/dev/null 2>&1; then
    if tgdb_systemctl_try "$scope" is-active -- podman.socket >/dev/null 2>&1; then
      return 0
    fi
    if [ "$scope" = "system" ]; then
      echo "正在為 system scope 啟用 Podman Socket（podman.sock）..." >&2
    else
      echo "正在為目前使用者啟用 Podman Socket（podman.sock）..." >&2
    fi
    if ! tgdb_systemctl_try "$scope" enable --now -- podman.socket >/dev/null 2>&1; then
      tgdb_warn "無法啟用 Podman Socket，請確認已安裝 Podman 並支援對應的 systemd scope。"
    fi
    return 0
  fi

  if [ "$scope" = "system" ]; then
    if _tgdb_run_privileged systemctl is-active --quiet podman.socket 2>/dev/null; then
      return 0
    fi
    echo "正在為 system scope 啟用 Podman Socket（podman.sock）..." >&2
    if ! _tgdb_run_privileged systemctl enable --now podman.socket >/dev/null 2>&1; then
      tgdb_warn "無法啟用 Podman Socket，請確認已安裝 Podman 並支援 systemd。"
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

_appspec_require_podman_socket_ready() {
  local service="$1"
  local v
  v="$(appspec_get "$service" "require_podman_socket" "0")"
  _appspec_truthy "$v" || return 0

  local deploy_mode socket_path
  deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"
  socket_path="$(_appspec_podman_sock_host_path "$service")"

  if _apps_test "$deploy_mode" -S "$socket_path"; then
    return 0
  fi

  tgdb_fail "需要的 Podman Socket 不存在或不是 socket：$socket_path（$service）。請先確認 podman.socket 已啟用。" 1 || true
  return 1
}

_appspec_hook_export_env() {
  local service="$1" name="$2"

  _appspec_export_env "TGDB_SERVICE" "$service" || true
  _appspec_export_env "TGDB_APP_NAME" "$name" || true

  # 匯出 ctx 內的所有變數（包含 input/var 與保留鍵）
  local prefix="${service}:${name}:"
  local full key value
  for full in "${!TGDB_APPSPEC_CTX[@]}"; do
    case "$full" in
      "${prefix}"*)
        key="${full#"$prefix"}"
        value="${TGDB_APPSPEC_CTX[$full]}"
        _appspec_env_key_is_valid "$key" || continue
        _appspec_export_env "$key" "$value" || true
        ;;
    esac
  done

  # 另外把 input=/var= 宣告的 env= 鍵也補齊（方便腳本使用大寫 ENV_KEY，不必解析 .env）
  local line def_key env_key
  local -A opts=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opts=()
    _appspec_parse_pipe_def "$line" def_key opts || true
    [ -n "$def_key" ] || continue
    env_key="${opts[env]:-}"
    [ -n "$env_key" ] || continue
    value="$(_appspec_ctx_get "$service" "$name" "$def_key" "")"
    [ -n "$value" ] || continue
    _appspec_export_env "$env_key" "$value" || true
  done < <(appspec_get_all "$service" "input" 2>/dev/null || true)

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    opts=()
    _appspec_parse_pipe_def "$line" def_key opts || true
    [ -n "$def_key" ] || continue
    env_key="${opts[env]:-}"
    [ -n "$env_key" ] || continue
    value="$(_appspec_ctx_get "$service" "$name" "$def_key" "")"
    [ -n "$value" ] || continue
    _appspec_export_env "$env_key" "$value" || true
  done < <(appspec_get_all "$service" "var" 2>/dev/null || true)
}

_appspec_run_hook_scripts() {
  local service="$1" name="$2" instance_dir="$3" host_port="$4" hook_key="$5"

  # hook 腳本預設以「目前使用者」執行；但若是 rootful 部署，
  # 腳本內直接呼叫 podman 時應改走 root Podman（system scope）。
  # 這裡用「只覆寫 podman 指令」的方式提供最小提權面（避免整支腳本都用 sudo 執行）。
  local deploy_mode podman_bin
  deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"
  podman_bin=""
  if [ "$deploy_mode" = "rootful" ]; then
    podman_bin="$(command -v podman 2>/dev/null || true)"
  fi

  local raw
  raw="$(appspec_get_all "$service" "$hook_key" 2>/dev/null || true)"
  [ -n "$raw" ] || return 0

  local line script_rel
  while IFS= read -r line; do
    [ -n "$line" ] || continue

    local -A opts=()
    _appspec_parse_pipe_def "$line" script_rel opts || true
    [ -n "$script_rel" ] || continue

    local allow_fail runner
    allow_fail="${opts[allow_fail]:-0}"
    runner="${opts[runner]:-bash}"

    local script
    script="$(_appspec_join_service_path "$service" "$script_rel")" || return 1
    if [ ! -f "$script" ]; then
      if _appspec_truthy "$allow_fail"; then
        tgdb_warn "找不到 ${hook_key} 腳本，已略過（$service）：$script_rel"
        continue
      fi
      tgdb_fail "找不到 ${hook_key} 腳本（$service）：$script_rel" 1 || true
      return 1
    fi

    local rc=0
    case "$runner" in
      source)
        (
          _appspec_hook_export_env "$service" "$name"

          if [ "$deploy_mode" = "rootful" ] && [ -n "$podman_bin" ]; then
            # 讓 hook 腳本可直接使用 podman 操作 rootful 容器。
            # 注意：export -f 只對 bash 子行程有效；source runner 直接在本 subshell 生效。
            TGDB_HOOK_PODMAN_BIN="$podman_bin"
            export TGDB_HOOK_PODMAN_BIN
            podman() {
              if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
                "$TGDB_HOOK_PODMAN_BIN" "$@"
                return $?
              fi
              if command -v sudo >/dev/null 2>&1; then
                sudo "$TGDB_HOOK_PODMAN_BIN" "$@"
                return $?
              fi
              echo "❌ 本操作需要 root 權限，且系統未安裝 sudo。" >&2
              return 1
            }
            export -f podman 2>/dev/null || true
          fi

          set -- "$service" "$name" "$instance_dir" "$host_port"
          # shellcheck disable=SC1090 # 腳本由 app.spec 指定，於執行期載入
          source "$script"
        ) || rc=$?
        ;;
      bash|"")
        (
          _appspec_hook_export_env "$service" "$name"

          if [ "$deploy_mode" = "rootful" ] && [ -n "$podman_bin" ]; then
            # 同 source runner：在 bash 子行程內覆寫 podman，改以 sudo/root 執行。
            TGDB_HOOK_PODMAN_BIN="$podman_bin"
            export TGDB_HOOK_PODMAN_BIN
            podman() {
              if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
                "$TGDB_HOOK_PODMAN_BIN" "$@"
                return $?
              fi
              if command -v sudo >/dev/null 2>&1; then
                sudo "$TGDB_HOOK_PODMAN_BIN" "$@"
                return $?
              fi
              echo "❌ 本操作需要 root 權限，且系統未安裝 sudo。" >&2
              return 1
            }
            export -f podman 2>/dev/null || true
          fi

          bash "$script" "$service" "$name" "$instance_dir" "$host_port"
        ) || rc=$?
        ;;
      *)
        tgdb_warn "不支援的 ${hook_key} runner（$service）：$runner，將改用 bash"
        (
          _appspec_hook_export_env "$service" "$name"

          if [ "$deploy_mode" = "rootful" ] && [ -n "$podman_bin" ]; then
            TGDB_HOOK_PODMAN_BIN="$podman_bin"
            export TGDB_HOOK_PODMAN_BIN
            podman() {
              if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
                "$TGDB_HOOK_PODMAN_BIN" "$@"
                return $?
              fi
              if command -v sudo >/dev/null 2>&1; then
                sudo "$TGDB_HOOK_PODMAN_BIN" "$@"
                return $?
              fi
              echo "❌ 本操作需要 root 權限，且系統未安裝 sudo。" >&2
              return 1
            }
            export -f podman 2>/dev/null || true
          fi

          bash "$script" "$service" "$name" "$instance_dir" "$host_port"
        ) || rc=$?
        ;;
    esac

    if [ "$rc" -ne 0 ]; then
      if _appspec_truthy "$allow_fail"; then
        tgdb_warn "${hook_key} 執行失敗但已忽略（$service/$name）：$script_rel（rc=$rc）"
        continue
      fi
      tgdb_fail "${hook_key} 執行失敗（$service/$name）：$script_rel（rc=$rc）" 1 || true
      return 1
    fi
  done <<< "$raw"

  return 0
}
