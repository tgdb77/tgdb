#!/bin/bash

# TGDB CLI 模式 - 精簡版
# 使用統一映射表 + 模板函式，減少重複程式碼

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_CORE_CLI_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_CLI_LOADED=1

# 共用路由表/註冊表
CLI_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/core/bootstrap.sh
[ -f "$CLI_CORE_DIR/bootstrap.sh" ] && source "$CLI_CORE_DIR/bootstrap.sh"
# shellcheck source=src/core/routes.sh
[ -f "$CLI_CORE_DIR/routes.sh" ] && source "$CLI_CORE_DIR/routes.sh"

# ---- 模組載入器 ----
_cli_load_module() {
  if declare -F tgdb_load_module >/dev/null 2>&1; then
    tgdb_load_module "$1"
    return $?
  fi

  if declare -F tgdb_fail >/dev/null 2>&1; then
    tgdb_fail "CLI 核心缺少 tgdb_load_module（請確認 src/core/routes.sh 已載入）。" 1 || return $?
  else
    echo "❌ CLI 核心缺少 tgdb_load_module（請確認 src/core/routes.sh 已載入）。" >&2
  fi
  return 1
}

_cli_usage_error() {
  tgdb_fail "用法/參數錯誤，請使用 -h 查看說明。" 2 || return $?
}

# ---- 通用模板函式 ----

_cli_app_quick() {
  local service="$1"; shift
  _cli_load_module "apps-p" || return 1

  if ! _ensure_podman_version_for_quadlet; then
    return 1
  fi

  local min_args=2
  local provided_args="$#"
  if declare -F _app_fn_exists >/dev/null 2>&1 && _app_fn_exists "$service" cli_quick_min_args; then
    min_args="$(_app_invoke "$service" cli_quick_min_args 2>/dev/null || echo 2)"
    if [[ ! "${min_args:-}" =~ ^[0-9]+$ ]] || [ "$min_args" -lt 2 ] 2>/dev/null; then
      min_args=2
    fi
  fi

  if [ "$provided_args" -lt "$min_args" ]; then
    _cli_usage_error
    return 2
  fi

  local name_code="$1" port_code="$2"
  shift 2

  local name host_port instance_dir
  if [ "$name_code" = "0" ]; then
    name=$(get_next_available_app_name "$service")
  else
    name="$name_code"
    if _is_app_name_duplicate "$name"; then
      tgdb_fail "已存在相同名稱：$name，請改用其他名稱或使用 0 自動命名。" 1 || return $?
      return 1
    fi
  fi

  if [ "$port_code" = "0" ]; then
    local base_port
    base_port=$(_app_invoke "$service" default_base_port 2>/dev/null || echo "")
    if [[ "$base_port" =~ ^[0-9]+$ ]] && [ "$base_port" -gt 0 ] 2>/dev/null; then
      host_port=$(get_next_available_port "$base_port")
    else
      tgdb_fail "找不到 $service 的預設端口。" 1 || return $?
    fi
  else
    if [[ "$port_code" =~ ^[0-9]+$ ]]; then
      host_port="$port_code"
    else
      _cli_usage_error
      return 2
    fi
  fi

  if _is_port_in_use "$host_port"; then
    tgdb_fail "埠號 $host_port 已被占用，請改用其他埠號。" 1 || return $?
  fi

  instance_dir="$TGDB_DIR/$name"
  _deploy_app_cli_quick "$service" "$name" "$host_port" "$instance_dir" "$@"
}

# 應用更新版本（通用）
_cli_app_update() {
  local service="$1" name="$2"
  _cli_load_module "apps-p" || return 1
  local default_image
  default_image="$(_apps_service_default_image "$service")"
  _service_update_and_restart "$service" "$default_image" "$name"
}

# 應用完全移除（通用）
_cli_app_remove() {
  local service="$1" name="$2" delete_flag="$3" delete_volume_flag="${4:-0}"
  case "$delete_flag" in
    0|1) ;;
    *) _cli_usage_error; return 2 ;;
  esac
  case "$delete_volume_flag" in
    0|1) ;;
    *) _cli_usage_error; return 2 ;;
  esac

  _cli_load_module "apps-p" || return 1
  local default_image
  default_image="$(_apps_service_default_image "$service")"
  _full_remove_instance "$service" "$default_image" "$name" "$delete_flag" "$delete_volume_flag"
}

_cli_app_deploy_from_record() {
  local service="$1" name="$2"
  _cli_load_module "apps-p" || return 1
  deploy_from_record_p "$service" "$name"
}

_cli_app_edit_record() {
  local service="$1" name="$2"
  _cli_load_module "apps-p" || return 1
  edit_record_cli "$service" "$name"
}

_cli_app_delete_record() {
  local service="$1" name="$2"
  _cli_load_module "apps-p" || return 1
  delete_record_cli "$service" "$name"
}

# ---- 咒語映射表（單一來源）----
# 格式: "spell_key|module|function|min_args|max_args"
# spell_key: 由 _cli_parse_spell_key 產生，例如 4-1-、5-9-1 等
# module: 需載入的模組 (none 表示不需載入)
# max_args: 最多允許的參數數量（-1 代表不限制；未填則視為與 min_args 相同）

CLI_REGISTRY=()
if declare -p TGDB_CLI_REGISTRY_BASE >/dev/null 2>&1; then
  CLI_REGISTRY=("${TGDB_CLI_REGISTRY_BASE[@]}")
fi
TGDB_CLI_APPS_COUNT=0

# 主選單 6 (應用)
# Apps 由 src/apps-p.sh 動態探索，並依 menu_order 排序後自動註冊：
# - 6 <idx> 1：快速部署
# - 6 <idx> 5：更新版本
# - 6 <idx> 6：完全移除

_cli_register_apps() {
  if [ "${__CLI_APPS_REGISTERED:-0}" = "1" ]; then
    return 0
  fi

  _cli_load_module "apps-p" || return 1

  local -a services=()
  local s
  while IFS= read -r s; do
    [ -n "$s" ] && services+=("$s")
  done < <(_apps_list_services)

  local i idx service
  for i in "${!services[@]}"; do
    idx=$((i + 1))
    service="${services[$i]}"
    # 註冊階段僅先掛上最小基準 2；
    # 各服務的實際最小參數（cli_quick_min_args）延後到執行該服務時再檢查，
    # 可避免每次啟動 CLI 都掃描全部服務動作造成卡頓。
    CLI_REGISTRY+=("6-${idx}-1|@app_quick|${service}|2|-1")
    CLI_REGISTRY+=("6-${idx}-2|@app_deploy_from_record|${service}|1")
    CLI_REGISTRY+=("6-${idx}-3|@app_edit_record|${service}|1")
    CLI_REGISTRY+=("6-${idx}-4|@app_delete_record|${service}|1")
    CLI_REGISTRY+=("6-${idx}-5|@app_update|${service}|1")
    CLI_REGISTRY+=("6-${idx}-6|@app_remove|${service}|2|3")
  done

  TGDB_CLI_APPS_COUNT="${#services[@]}"
  __CLI_APPS_REGISTERED=1
  return 0
}

_cli_parse_apps_spell_fast() {
  local idx="${1:-}" action="${2:-}"
  shift 2 2>/dev/null || true

  if [[ ! "$idx" =~ ^[0-9]+$ ]] || [[ ! "$action" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if [ "$idx" -lt 1 ] || [ "$idx" -gt "${TGDB_CLI_APPS_COUNT:-0}" ]; then
    return 1
  fi

  if [ "$action" -lt 1 ] || [ "$action" -gt 6 ]; then
    return 1
  fi

  PARSED_SPELL_KEY="6-${idx}-${action}"
  PARSED_PARAMS=("$@")
  return 0
}

_cli_lookup_entry() {
  local spell_key="$1"
  local row key module func min_args max_args

  case "$spell_key" in
    6-*-*)
      _cli_register_apps || return 1
      ;;
  esac

  for row in "${CLI_REGISTRY[@]}"; do
    IFS='|' read -r key module func min_args max_args <<< "$row"
    if [ "$key" = "$spell_key" ]; then
      [ -z "${max_args:-}" ] && max_args="$min_args"
      printf '%s|%s|%s|%s\n' "$module" "$func" "$min_args" "$max_args"
      return 0
    fi
  done

  return 1
}

# ---- 核心路由器 ----
_cli_dispatch() {
  local spell_key="$1"; shift
  local entry

  if ! entry=$(_cli_lookup_entry "$spell_key"); then
    tgdb_fail "未支援的咒語：$spell_key" 3 || return $?
  fi

  IFS='|' read -r module func min_args max_args <<< "$entry"
  [ -z "${max_args:-}" ] && max_args="$min_args"

  if [ "$#" -lt "$min_args" ]; then
    _cli_usage_error
    return 2
  fi

  if [ "$max_args" != "-1" ] && [ "$#" -gt "$max_args" ]; then
    tgdb_warn "已忽略多餘參數：${*:$((max_args+1))}"
    set -- "${@:1:$max_args}"
  fi

  if [[ "$module" == @* ]]; then
    case "$module" in
      "@app_quick")  _cli_app_quick "$func" "$@" ;;
      "@app_deploy_from_record") _cli_app_deploy_from_record "$func" "$@" ;;
      "@app_edit_record") _cli_app_edit_record "$func" "$@" ;;
      "@app_delete_record") _cli_app_delete_record "$func" "$@" ;;
      "@app_update") _cli_app_update "$func" "$@" ;;
      "@app_remove") _cli_app_remove "$func" "$@" ;;
      *) tgdb_fail "未知的模板：$module" 3 || return $? ;;
    esac
    return $?
  fi

  if [ "$module" != "none" ]; then
    _cli_load_module "$module" || return 1
  fi

  "$func" "$@"
}

# ---- 解析咒語鍵（直接依 CLI_REGISTRY 配對）----
_cli_spell_key_to_path() {
  local spell_key="$1"
  local path="$spell_key"

  while [[ "$path" == *- ]]; do
    path="${path%-}"
  done

  printf '%s' "$path"
}

_cli_registry_find_best_key() {
  local -a input_tokens=("$@")
  local row key module func min_args max_args
  local path depth i matched
  local -a key_tokens=()
  local best_key="" best_depth=0
  local main_code="${input_tokens[0]:-}"

  for row in "${CLI_REGISTRY[@]}"; do
    IFS='|' read -r key module func min_args max_args <<< "$row"
    if [ -n "$main_code" ] && [[ "$key" != "${main_code}-"* ]]; then
      continue
    fi
    path="$(_cli_spell_key_to_path "$key")"
    [ -z "$path" ] && continue
    IFS='-' read -r -a key_tokens <<< "$path"
    depth=${#key_tokens[@]}
    [ "${#input_tokens[@]}" -lt "$depth" ] && continue

    matched=1
    for ((i=0; i<depth; i++)); do
      if [ "${input_tokens[$i]}" != "${key_tokens[$i]}" ]; then
        matched=0
        break
      fi
    done

    if [ "$matched" -eq 1 ] && [ "$depth" -gt "$best_depth" ]; then
      best_key="$key"
      best_depth="$depth"
    fi
  done

  if [ -n "$best_key" ]; then
    PARSED_SPELL_KEY="$best_key"
    PARSED_PARAMS=("${input_tokens[@]:$best_depth}")
    return 0
  fi

  return 1
}

_cli_registry_has_incomplete_prefix() {
  local -a input_tokens=("$@")
  local row key module func min_args max_args
  local path depth i matched
  local -a key_tokens=()
  local main_code="${input_tokens[0]:-}"

  for row in "${CLI_REGISTRY[@]}"; do
    IFS='|' read -r key module func min_args max_args <<< "$row"
    if [ -n "$main_code" ] && [[ "$key" != "${main_code}-"* ]]; then
      continue
    fi
    path="$(_cli_spell_key_to_path "$key")"
    [ -z "$path" ] && continue
    IFS='-' read -r -a key_tokens <<< "$path"
    depth=${#key_tokens[@]}
    [ "${#input_tokens[@]}" -ge "$depth" ] && continue

    matched=1
    for ((i=0; i<${#input_tokens[@]}; i++)); do
      if [ "${input_tokens[$i]}" != "${key_tokens[$i]}" ]; then
        matched=0
        break
      fi
    done

    if [ "$matched" -eq 1 ]; then
      return 0
    fi
  done

  return 1
}

_cli_registry_has_main_code() {
  local main_code="$1"
  local row key module func min_args max_args

  for row in "${CLI_REGISTRY[@]}"; do
    IFS='|' read -r key module func min_args max_args <<< "$row"
    if [[ "$key" == "${main_code}-"* ]]; then
      return 0
    fi
  done

  return 1
}

_cli_parse_spell_key() {
  local main_code="$1"; shift
  local -a input_tokens=("$main_code" "$@")

  case "$main_code" in
    6)
      _cli_register_apps || return 1
      if _cli_parse_apps_spell_fast "$@"; then
        return 0
      fi
      ;;
  esac

  # 主選單 8（第三方腳本）僅支援互動模式（TTY）。
  if [ "$main_code" = "8" ]; then
    tgdb_fail "第三方腳本僅支援互動模式（TTY），請執行 ./tgdb.sh 後於主選單選 8。" 3 || return $?
    return 3
  fi

  if _cli_registry_find_best_key "${input_tokens[@]}"; then
    return 0
  fi

  if _cli_registry_has_incomplete_prefix "${input_tokens[@]}"; then
    _cli_usage_error
    return 2
  fi

  if ! _cli_registry_has_main_code "$main_code"; then
    tgdb_fail "未支援的主選單咒語：$main_code" 3 || true
    print_cli_help 2>/dev/null || true
    return 3
  fi

  tgdb_fail "未支援的咒語：${input_tokens[*]}" 3 || return $?
  return 3
}

# ---- Help ----
print_cli_help() {
  cat <<'EOF'
==================================
❖ TGDB CLI 咒語模式說明 ❖
==================================
核心概念：
  - CLI 路徑對標 TTY 選單路徑，輸入順序就是「主選單 -> 子選單 -> 功能」。
  - 例：部屬Excalidraw是 6 -> 1 -> 1 -> 輸入變數，CLI 就是 `t 6 1 1 [參數...]`。

通用語法：
  t(快捷鍵) <功能路徑> [參數...]

共通規則：
  - CLI 不會再互動式提問，需一次輸入完整參數。
  - 代碼 0 代表使用預設值（僅限該功能有支援）。
  - 參數 a 代表「全部」（僅限支援批次的功能）；使用 a 時需額外輸入確認參數 <0|1>。
  - 退出碼：0=成功，2=用法/參數錯誤，1=執行錯誤，3=未支援/僅互動功能。

與 TTY 不同處（重點）：
  - 主選單 8（第三方腳本）僅支援互動模式（TTY），不提供 CLI 咒語。
  - 主選單 3 為內部流程（env_setup）使用，不在一般 CLI 流程公開。
  - 需編輯器或互動輸入的功能，建議改走 TTY。

常用範例：
  t 1
  t 5 5 a 0
  t 5 6 myapp.container mypod.pod
  t 5 7 a 1
  t 5 9 1 docker.io/library/nginx:latest
  t 5 9 2 alpine:latest busybox:latest
  t 5 10 3 0
  t 7 2 11 2 200
  t 6 <idx> 1 <name|0> <port|0> [額外參數...]

補充：
  - 主選單/子選單代碼以互動選單顯示為準。
  - 應用管理（6）的 <idx> 依 TTY 應用列表排序（從 1 開始）。
==================================
EOF
}

# ---- 入口 ----
cli_entry() {
  export TGDB_CLI_MODE=1

  if [ "$#" -eq 0 ]; then
    _cli_usage_error
    return 2
  fi

  local first_arg="$1"
  if [ "$first_arg" = "-h" ] || [ "$first_arg" = "--help" ]; then
    print_cli_help 2>/dev/null || true
    return 0
  fi

  if [[ "$first_arg" == -* ]]; then
    _cli_usage_error
    return 2
  fi

  local main_code="$1"; shift

  # 解析咒語鍵
  _cli_parse_spell_key "$main_code" "$@" || return $?

  # 執行
  _cli_dispatch "$PARSED_SPELL_KEY" "${PARSED_PARAMS[@]}"
  local status=$?
  case "$status" in
    0|2|3) return "$status" ;;
    *) return 1 ;;
  esac
}
