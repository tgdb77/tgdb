#!/bin/bash

# TGDB AppSpec 執行器：互動輸入/var/CLI quick
# 注意：
# - 本檔案為 library，會被 src/apps/app_spec_exec.sh source
# - 請勿在此更改 shell options（例如 set -euo pipefail）。

_appspec_input_def_opts() {
  local service="$1" input_key="$2"
  # shellcheck disable=SC2178 # out_opts_ref 透過 nameref 回傳（shellcheck 誤判）
  local -n out_opts_ref="$3"

  out_opts_ref=()
  [ -n "${service:-}" ] || return 1
  [ -n "${input_key:-}" ] || return 1

  local line def_name
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local -A def_opts=()
    _appspec_parse_pipe_def "$line" def_name def_opts || true
    [ -z "$def_name" ] && continue
    if [ "$def_name" = "$input_key" ]; then
      out_opts_ref=()
      local k
      for k in "${!def_opts[@]}"; do
        # shellcheck disable=SC2034 # out_opts_ref 透過 nameref 回傳（shellcheck 誤判）
        out_opts_ref["$k"]="${def_opts[$k]}"
      done
      return 0
    fi
  done < <(appspec_get_all "$service" "input" 2>/dev/null || true)

  return 1
}

_appspec_input_validate_value() {
  local service="$1" name="$2" input_key="$3" value="$4"
  local -n opts_ref="$5"

  local min_len max_len
  min_len="${opts_ref[min_len]:-}"
  max_len="${opts_ref[max_len]:-}"

  if [[ "$min_len" =~ ^[0-9]+$ ]] && [ "${#value}" -lt "$min_len" ]; then
    tgdb_fail "輸入 '$input_key' 長度不足（$service；至少 ${min_len} 個字元）。" 1 || true
    return 1
  fi

  if [[ "$max_len" =~ ^[0-9]+$ ]] && [ "${#value}" -gt "$max_len" ]; then
    tgdb_fail "輸入 '$input_key' 長度過長（$service；最多 ${max_len} 個字元）。" 1 || true
    return 1
  fi

  if _appspec_truthy "${opts_ref[require_upper]:-0}" && [[ ! "$value" =~ [A-Z] ]]; then
    tgdb_fail "輸入 '$input_key' 必須至少包含一個大寫英文字母（$service）。" 1 || true
    return 1
  fi

  if _appspec_truthy "${opts_ref[require_lower]:-0}" && [[ ! "$value" =~ [a-z] ]]; then
    tgdb_fail "輸入 '$input_key' 必須至少包含一個小寫英文字母（$service）。" 1 || true
    return 1
  fi

  if _appspec_truthy "${opts_ref[require_digit]:-0}" && [[ ! "$value" =~ [0-9] ]]; then
    tgdb_fail "輸入 '$input_key' 必須至少包含一個數字（$service）。" 1 || true
    return 1
  fi

  if _appspec_truthy "${opts_ref[require_special]:-0}" && [[ ! "$value" =~ [^[:alnum:]] ]]; then
    tgdb_fail "輸入 '$input_key' 必須至少包含一個特殊字元（$service）。" 1 || true
    return 1
  fi

  local pattern
  pattern="${opts_ref[pattern]:-}"
  if [ -n "${pattern:-}" ]; then
    if [[ ! "$value" =~ $pattern ]]; then
      local msg
      msg="${opts_ref[pattern_msg]:-}"
      if [ -z "${msg:-}" ]; then
        msg="輸入 '$input_key' 格式不符合規則（$service）。"
      fi
      tgdb_fail "$msg" 1 || true
      return 1
    fi
  fi

  local no_space
  no_space="${opts_ref[no_space]:-0}"
  if _appspec_truthy "$no_space"; then
    if [[ "$value" =~ [[:space:]] ]]; then
      tgdb_fail "輸入 '$input_key' 不可包含空白（$service）。" 1 || true
      return 1
    fi
  fi

  local disallow
  disallow="${opts_ref[disallow]:-}"
  if [ -n "${disallow:-}" ] && [ -n "${value:-}" ]; then
    local i ch
    for ((i = 0; i < ${#disallow}; i++)); do
      ch="${disallow:i:1}"
      if [[ "$value" == *"$ch"* ]]; then
        tgdb_fail "輸入 '$input_key' 不可包含字元 '$ch'（$service）。" 1 || true
        return 1
      fi
    done
  fi

  local type
  type="${opts_ref[type]:-string}"
  if [ "$type" = "port" ] && [ -n "${value:-}" ]; then
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "$value" -le 0 ] 2>/dev/null || [ "$value" -gt 65535 ] 2>/dev/null; then
      tgdb_fail "輸入 '$input_key' 無效：$value（$service；請輸入 1-65535）。" 1 || true
      return 1
    fi

    local avoid_raw
    avoid_raw="${opts_ref[avoid]:-}"
    if [ -n "$avoid_raw" ]; then
      local tok
      for tok in ${avoid_raw//,/ }; do
        tok="$(_appspec_trim_ws "$tok")"
        [ -z "$tok" ] && continue
        local av=""
        if [[ "$tok" =~ ^[0-9]+$ ]]; then
          av="$tok"
        else
          av="$(_appspec_ctx_get "$service" "$name" "$tok" "")"
        fi
        if [ -n "$av" ] && [ "$value" = "$av" ]; then
          tgdb_fail "輸入 '$input_key' 不可與 '$tok' 相同：$value（$service）。" 1 || true
          return 1
        fi
      done
    fi

    local check_available
    check_available="${opts_ref[check_available]:-0}"
    if _appspec_truthy "$check_available"; then
      if declare -F _is_port_in_use >/dev/null 2>&1; then
        if _is_port_in_use "$value"; then
          tgdb_fail "輸入 '$input_key' 埠號已被占用：$value（$service）。" 1 || true
          return 1
        fi
      fi
    fi
  fi

  return 0
}

_appspec_default_from_source() {
  local service="$1" name="$2" input_key="$3"
  local -n opts_ref="$4"

  local source
  source="${opts_ref[default_source]:-}"
  [ -n "$source" ] || return 1

  case "$source" in
    random_hex)
      local len prefix hex
      len="${opts_ref[len]:-32}"
      prefix="${opts_ref[prefix]:-}"
      hex="$(_appspec_random_hex "$len")"
      printf '%s\n' "${prefix}${hex}"
      return 0
      ;;
    strong_password)
      local pw_len prefix pw
      pw_len="${opts_ref[len]:-20}"
      prefix="${opts_ref[prefix]:-}"
      pw="$(_appspec_random_password "$pw_len")"
      printf '%s\n' "${prefix}${pw}"
      return 0
      ;;
    hostname)
      # 取用宿主機 hostname 作為預設值（常用於 instance/node 名稱）
      # - 盡量避免引入額外相依；優先用 hostname 指令，失敗再讀 /etc/hostname
      local hn=""
      if command -v hostname >/dev/null 2>&1; then
        hn="$(hostname 2>/dev/null || true)"
      fi
      if [ -z "${hn:-}" ] && [ -r /etc/hostname ]; then
        hn="$(cat /etc/hostname 2>/dev/null || true)"
      fi
      hn="$(_appspec_trim_ws "${hn:-}")"
      if [ -z "${hn:-}" ]; then
        tgdb_warn "無法取得 hostname，無法產生預設值（$service）：$input_key"
        return 1
      fi
      printf '%s\n' "$hn"
      return 0
      ;;
    next_available_port)
      local start
      start="${opts_ref[start]:-}"
      if [[ ! "$start" =~ ^[0-9]+$ ]] || [ "$start" -le 0 ] 2>/dev/null || [ "$start" -gt 65535 ] 2>/dev/null; then
        start=1
      fi

      if ! declare -F get_next_available_port >/dev/null 2>&1; then
        tgdb_warn "找不到 get_next_available_port，無法產生預設值（$service）：$input_key"
        return 1
      fi

      local port
      port="$(get_next_available_port "$start")"

      # avoid：避免與其他 key（或固定數字）相同，例如 avoid=host_port
      local avoid_raw
      avoid_raw="${opts_ref[avoid]:-}"
      if [ -n "$avoid_raw" ]; then
        local tok
        for tok in ${avoid_raw//,/ }; do
          tok="$(_appspec_trim_ws "$tok")"
          [ -z "$tok" ] && continue
          local av=""
          if [[ "$tok" =~ ^[0-9]+$ ]]; then
            av="$tok"
          else
            av="$(_appspec_ctx_get "$service" "$name" "$tok" "")"
          fi
          if [ -n "$av" ] && [ "$port" = "$av" ]; then
            port="$(get_next_available_port $((port + 1)))"
          fi
        done
      fi

      printf '%s\n' "$port"
      return 0
      ;;
    *)
      tgdb_warn "忽略不支援的 default_source（$service）：$input_key（default_source=$source）"
      return 1
      ;;
  esac
}

_appspec_input_prompt_value() {
  local service="$1" name="$2" input_key="$3"
  local out_var="$4"
  local opts_var="$5"
  local -n opts_ref="$opts_var"

  if ! ui_is_interactive; then
    tgdb_fail "非互動模式下不可使用互動輸入：$input_key（$service）" 2 || return $?
  fi

  local required type prompt default_value allow_cancel
  required="${opts_ref[required]:-0}"
  type="${opts_ref[type]:-string}"
  prompt="${opts_ref[prompt]:-}"
  default_value="${opts_ref[default]:-}"
  allow_cancel="${opts_ref[allow_cancel]:-0}"

  if [ -z "$prompt" ]; then
    prompt="請輸入 ${input_key}: "
  fi

  local input_value=""
  while true; do
    if [ "$type" = "port" ]; then
      local label rc out
      label="$prompt"
      out="$(prompt_available_port "$label" "$default_value")"
      rc=$?
      if [ "$rc" -eq 2 ]; then
        if _appspec_truthy "$allow_cancel"; then
          return 2
        fi
        tgdb_err "此欄位不可取消，請重新輸入。"
        continue
      fi
      if [ "$rc" -ne 0 ]; then
        return 1
      fi
      input_value="$out"
    elif [ "$type" = "password" ]; then
      read -r -s -p "$prompt" input_value
      printf '\n' >&2
    else
      read -r -e -p "$prompt" input_value
    fi

    if _appspec_truthy "$allow_cancel" && [ "$input_value" = "0" ]; then
      return 2
    fi

    if [ -z "$input_value" ] && [ -n "${default_value:-}" ]; then
      input_value="$default_value"
    fi

    if [ -z "$input_value" ] && _appspec_truthy "$required"; then
      tgdb_err "此欄位不得為空，請重新輸入。"
      continue
    fi

    if [ -n "$input_value" ]; then
      if ! _appspec_input_validate_value "$service" "$name" "$input_key" "$input_value" "$opts_var"; then
        tgdb_err "輸入格式不正確，請重新輸入。"
        continue
      fi
    fi

    printf -v "$out_var" '%s' "$input_value"
    return 0
  done
}

_appspec_collect_inputs() {
  local service="$1" name="$2"

  local line input_key
  while IFS= read -r line <&3; do
    [ -z "$line" ] && continue

    local -A opts=()
    _appspec_parse_pipe_def "$line" input_key opts || true
    [ -z "$input_key" ] && continue

    # 支援 default_source（例如：next_available_port）
    if [ -z "${opts[default]+x}" ] && [ -n "${opts[default_source]:-}" ]; then
      local computed_default=""
      computed_default="$(_appspec_default_from_source "$service" "$name" "$input_key" opts 2>/dev/null || true)"
      if [ -n "$computed_default" ]; then
        opts[default]="$computed_default"
      fi
    fi

    local from_ctx=0 from_env=0
    local value=""
    if _appspec_ctx_has "$service" "$name" "$input_key"; then
      value="$(_appspec_ctx_get "$service" "$name" "$input_key" "")"
      from_ctx=1
    fi

    local env_key
    env_key="${opts[env]:-}"
    if [ -z "$value" ] && [ -n "$env_key" ]; then
      if declare -F _env_key_is_valid >/dev/null 2>&1; then
        if _env_key_is_valid "$env_key"; then
          value="${!env_key-}"
          [ -n "$value" ] && from_env=1
        fi
      else
        value="${!env_key-}"
        [ -n "$value" ] && from_env=1
      fi
    fi

    if [ -z "$value" ] && [ -n "${opts[default]+x}" ]; then
      value="${opts[default]}"
    fi

    local required ask
    required="${opts[required]:-0}"
    ask="${opts[ask]:-0}"

    if ui_is_interactive; then
      if [ -z "$value" ] && _appspec_truthy "$required"; then
        _appspec_input_prompt_value "$service" "$name" "$input_key" value opts || return $?
      elif _appspec_truthy "$ask"; then
        # ask=1：互動模式提示一次（但若值已由 ctx/env 提供則略過）。
        # - ctx：視為使用者已提供（即使為空）
        # - env：僅當 env 值非空才視為已提供
        if [ "$from_ctx" -eq 0 ] && [ "$from_env" -eq 0 ]; then
          _appspec_input_prompt_value "$service" "$name" "$input_key" value opts || return $?
        fi
      fi
    fi

    if [ -z "$value" ] && _appspec_truthy "$required"; then
      tgdb_fail "缺少必要輸入：$input_key（$service）。" 2 || true
      return 2
    fi

    if [ -n "$value" ]; then
      _appspec_input_validate_value "$service" "$name" "$input_key" "$value" opts || return 1
    fi

    _appspec_ctx_set "$service" "$name" "$input_key" "$value"
    if [ -n "$env_key" ] && [ -n "$value" ]; then
      if ! _appspec_export_env "$env_key" "$value"; then
        tgdb_warn "忽略無效 env 鍵（$service）：$env_key"
      fi
    fi
  done 3< <(appspec_get_all "$service" "input" 2>/dev/null || true)

  return 0
}

_appspec_random_hex() {
  local want_len="${1:-32}"
  if [[ ! "$want_len" =~ ^[0-9]+$ ]] || [ "$want_len" -le 0 ] 2>/dev/null; then
    want_len=32
  fi

  local bytes=$(((want_len + 1) / 2))
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes" 2>/dev/null | cut -c1-"$want_len"
    return 0
  fi
  if [ -r /dev/urandom ] && command -v hexdump >/dev/null 2>&1; then
    hexdump -vn "$bytes" -e '/1 "%02x"' /dev/urandom 2>/dev/null | cut -c1-"$want_len"
    return 0
  fi
  date +%s%N | sha1sum | cut -c1-"$want_len"
}

_appspec_random_chars_from_set() {
  local charset="$1" want_len="${2:-1}"
  local out=""

  if [ -z "$charset" ]; then
    return 1
  fi
  if [[ ! "$want_len" =~ ^[0-9]+$ ]] || [ "$want_len" -le 0 ] 2>/dev/null; then
    want_len=1
  fi

  while [ "${#out}" -lt "$want_len" ]; do
    local need chunk
    need=$((want_len - ${#out}))
    chunk=""

    if [ -r /dev/urandom ]; then
      chunk="$(LC_ALL=C tr -dc "$charset" </dev/urandom 2>/dev/null | dd bs=1 count="$need" 2>/dev/null || true)"
    elif command -v openssl >/dev/null 2>&1; then
      chunk="$(openssl rand -base64 $((need * 8 + 16)) 2>/dev/null | tr -dc "$charset" | cut -c1-"$need")"
    fi

    if [ -z "$chunk" ]; then
      while [ "${#chunk}" -lt "$need" ]; do
        chunk+="${charset:$((RANDOM % ${#charset})):1}"
      done
    fi

    out+="$chunk"
  done

  printf '%s\n' "$out"
}

_appspec_random_password() {
  local want_len="${1:-20}"
  local upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  local lower='abcdefghijklmnopqrstuvwxyz'
  local digits='0123456789'
  local special='@%_+=' 
  local charset="${upper}${lower}${digits}${special}"
  local password=""

  if [[ ! "$want_len" =~ ^[0-9]+$ ]] || [ "$want_len" -lt 10 ] 2>/dev/null; then
    want_len=20
  fi

  while true; do
    password="$(_appspec_random_chars_from_set "$charset" "$want_len")" || return 1
    [[ "$password" =~ [A-Z] ]] || continue
    [[ "$password" =~ [a-z] ]] || continue
    [[ "$password" =~ [0-9] ]] || continue
    [[ "$password" =~ [^[:alnum:]] ]] || continue
    printf '%s\n' "$password"
    return 0
  done
}

_appspec_collect_vars() {
  local service="$1" name="$2"

  local line var_key
  while IFS= read -r line; do
    [ -z "$line" ] && continue

    local -A opts=()
    _appspec_parse_pipe_def "$line" var_key opts || true
    [ -z "$var_key" ] && continue

    if _appspec_ctx_has "$service" "$name" "$var_key"; then
      continue
    fi

    local value=""
    local env_key
    env_key="${opts[env]:-}"
    if [ -n "$env_key" ]; then
      if declare -F _env_key_is_valid >/dev/null 2>&1; then
        _env_key_is_valid "$env_key" || env_key=""
      elif [[ ! "$env_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        env_key=""
      fi
      if [ -n "$env_key" ] && [ -n "${!env_key-}" ]; then
        value="${!env_key}"
      fi
    fi

    if [ -z "$value" ]; then
      local source len prefix
      source="${opts[source]:-random_hex}"
      len="${opts[len]:-32}"
      prefix="${opts[prefix]:-}"
      case "$source" in
        random_hex)
          value="$(_appspec_random_hex "$len")"
          ;;
        *)
          tgdb_warn "忽略不支援的 var source（$service）：$var_key（source=$source）"
          continue
          ;;
      esac
      value="${prefix}${value}"
    fi

    _appspec_ctx_set "$service" "$name" "$var_key" "$value"
    if [ -n "$env_key" ] && [ -n "$value" ]; then
      _appspec_export_env "$env_key" "$value" || true
    fi
  done < <(appspec_get_all "$service" "var" 2>/dev/null || true)

  return 0
}

appspec_cli_quick_min_args() {
  local service="$1"
  local raw
  raw="$(appspec_get "$service" "cli_quick_args" "")"
  local -a segs=()
  read -r -a segs <<< "$raw"
  local last_seg=""
  if [ ${#segs[@]} -gt 0 ]; then
    last_seg="${segs[$(( ${#segs[@]} - 1 ))]}"
  fi
  local volume_dir_count=0
  local seg
  for seg in "${segs[@]}"; do
    [ -z "$seg" ] && continue
    if [ "$seg" = "volume_dir" ]; then
      volume_dir_count=$((volume_dir_count + 1))
    fi
  done
  local volume_dir_optional=0
  if [ "$volume_dir_count" -eq 1 ] && [ "$last_seg" = "volume_dir" ]; then
    volume_dir_optional=1
  fi
  local count=0 seg
  for seg in $raw; do
    [ -z "$seg" ] && continue
    case "$seg" in
      volume_dir)
        if [ "$volume_dir_optional" -ne 1 ]; then
          count=$((count + 1))
        fi
        ;;
      *)
        local -A opts=()
        if _appspec_input_def_opts "$service" "$seg" opts; then
          if _appspec_truthy "${opts[required]:-0}"; then
            count=$((count + 1))
          fi
        else
          # 未定義 input 的參數視為必填（避免 CLI 位移錯誤）
          count=$((count + 1))
        fi
        ;;
    esac
  done
  printf '%s\n' $((2 + count))
}

appspec_cli_quick_usage() {
  local service="$1"
  local raw
  raw="$(appspec_get "$service" "cli_quick_args" "")"
  if [ -z "$raw" ]; then
    printf '%s\n' ""
    return 0
  fi

  local out="" a
  local -a segs=()
  read -r -a segs <<< "$raw"
  local last_seg=""
  if [ ${#segs[@]} -gt 0 ]; then
    last_seg="${segs[$(( ${#segs[@]} - 1 ))]}"
  fi
  local volume_dir_count=0
  local seg
  for seg in "${segs[@]}"; do
    [ -z "$seg" ] && continue
    if [ "$seg" = "volume_dir" ]; then
      volume_dir_count=$((volume_dir_count + 1))
    fi
  done
  local volume_dir_optional=0
  if [ "$volume_dir_count" -eq 1 ] && [ "$last_seg" = "volume_dir" ]; then
    volume_dir_optional=1
  fi
  for a in $raw; do
    case "$a" in
      volume_dir)
        local backup_root
        if declare -F tgdb_backup_root >/dev/null 2>&1; then
          backup_root="$(tgdb_backup_root)"
        else
          backup_root="${TGDB_BACKUP_ROOT:-$(dirname "${TGDB_DIR:-$HOME/.tgdb/app}")}"
        fi
        if [ "$volume_dir_optional" -eq 1 ]; then
          out+="${out:+ }[volume_dir|0]（可省略；0=自動建立 ${backup_root}/volume/${service}/<name>）"
        else
          out+="${out:+ }<volume_dir|0>（0=自動建立 ${backup_root}/volume/${service}/<name>）"
        fi
        ;;
      *)
        local -A opts=()
        if _appspec_input_def_opts "$service" "$a" opts; then
          local desc="<$a>" notes=""
          if [ "${opts[type]:-string}" = "password" ]; then
            notes="密碼"
          fi
          if _appspec_truthy "${opts[zero_as_default]:-0}" || _appspec_truthy "${opts[cli_zero_as_default]:-0}"; then
            notes="${notes:+${notes}，}0=預設"
          fi
          if [ -n "$notes" ]; then
            desc+="（$notes）"
          fi
          out+="${out:+ }$desc"
        else
          out+="${out:+ }<$a>"
        fi
        ;;
    esac
  done

  printf '額外參數：%s\n' "$out"
}

appspec_cli_quick() {
  local service="$1" name="$2" host_port="$3" instance_dir="$4"
  shift 4 || true

  local raw
  raw="$(appspec_get "$service" "cli_quick_args" "")"
  local -a segs=()
  read -r -a segs <<< "$raw"
  local last_seg=""
  if [ ${#segs[@]} -gt 0 ]; then
    last_seg="${segs[$(( ${#segs[@]} - 1 ))]}"
  fi
  local volume_dir_count=0
  local seg
  for seg in "${segs[@]}"; do
    [ -z "$seg" ] && continue
    if [ "$seg" = "volume_dir" ]; then
      volume_dir_count=$((volume_dir_count + 1))
    fi
  done
  local volume_dir_optional=0
  if [ "$volume_dir_count" -eq 1 ] && [ "$last_seg" = "volume_dir" ]; then
    volume_dir_optional=1
  fi

  local volume_dir=""
  local a v
  for a in $raw; do
    v="${1:-}"
    if [ -z "${v:-}" ]; then
      # 允許省略「尾端非必填」參數（以 input required=1 判斷）。
      if [ "$a" = "volume_dir" ]; then
        if [ "$volume_dir_optional" -eq 1 ]; then
          volume_dir="0"
          break
        else
          tgdb_fail "用法/參數錯誤，請使用 -h 查看說明。" 2 || true
          return 2
        fi
      fi
      local -A _opts=()
      if _appspec_input_def_opts "$service" "$a" _opts && _appspec_truthy "${_opts[required]:-0}"; then
        tgdb_fail "用法/參數錯誤，請使用 -h 查看說明。" 2 || true
        return 2
      fi
      break
    fi
    shift || true

    case "$a" in
      volume_dir)
        volume_dir="$v"
        ;;
      *)
        if declare -F _env_key_is_valid >/dev/null 2>&1; then
          if ! _env_key_is_valid "$a"; then
            tgdb_fail "用法/參數錯誤（AppSpec）：無效參數鍵：$a" 2 || true
            return 2
          fi
        elif [[ ! "$a" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          tgdb_fail "用法/參數錯誤（AppSpec）：無效參數鍵：$a" 2 || true
          return 2
        fi

        local -A opts=()
        if _appspec_input_def_opts "$service" "$a" opts; then
          if [ "${v:-}" = "0" ] && { _appspec_truthy "${opts[zero_as_default]:-0}" || _appspec_truthy "${opts[cli_zero_as_default]:-0}"; }; then
            if [ -n "${opts[default]+x}" ]; then
              v="${opts[default]-}"
            elif [ -n "${opts[default_source]:-}" ]; then
              local computed_default=""
              computed_default="$(_appspec_default_from_source "$service" "$name" "$a" opts 2>/dev/null || true)"
              [ -n "$computed_default" ] && v="$computed_default"
            fi
          fi
          if [ -n "${v:-}" ]; then
            _appspec_input_validate_value "$service" "$name" "$a" "$v" opts || return 1
          fi
          if _appspec_truthy "${opts[allow_cancel]:-0}" && [ "${v:-}" = "0" ]; then
            return 2
          fi
          local env_key
          env_key="${opts[env]:-}"
          _appspec_ctx_set "$service" "$name" "$a" "$v"
          if [ -n "$env_key" ] && [ -n "$v" ]; then
            _appspec_export_env "$env_key" "$v" || tgdb_warn "忽略無效 env 鍵（$service）：$env_key"
          fi
        else
          _appspec_ctx_set "$service" "$name" "$a" "$v"
        fi
        ;;
    esac
  done

  if [ -n "${volume_dir:-}" ] && [ "${volume_dir:-}" != "0" ]; then
    local deploy_mode
    deploy_mode="$(_apps_current_deploy_mode 2>/dev/null || printf '%s\n' "rootless")"
    if _apps_test "$deploy_mode" -e "$volume_dir" && ! _apps_test "$deploy_mode" -d "$volume_dir"; then
      tgdb_fail "volume_dir 不是資料夾：$volume_dir" 1 || true
      return 1
    fi
    if _apps_test "$deploy_mode" -d "$volume_dir" && { ! _apps_test "$deploy_mode" -r "$volume_dir" || ! _apps_test "$deploy_mode" -w "$volume_dir"; }; then
      tgdb_fail "目前使用者對 $volume_dir 沒有讀寫權限，請調整權限或改用其他目錄。" 1 || true
      return 1
    fi
  fi

  local propagation="none" selinux_flag="none"
  local mount_out="" mount_line="" line=""

  mount_out="$(_apps_default_mount_options "$instance_dir")" || true
  while IFS= read -r line; do
    [ -n "$line" ] && mount_line="$line"
  done <<< "$mount_out"
  if [ -n "$mount_line" ]; then
    IFS=' ' read -r propagation selinux_flag <<< "$mount_line"
  fi

  _deploy_app_core "$service" "$name" "$host_port" "$instance_dir" "$propagation" "$selinux_flag" "$volume_dir"
}
