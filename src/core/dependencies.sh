#!/bin/bash

# TGDB 入口依賴檢查模組
# 目的：
# - 僅檢查「核心必備命令」
# - 缺少時在入口直接自動安裝

# 載入守衛：避免重複 source；需要重載時可設定 TGDB_FORCE_RELOAD_LIBS=1
if [ -n "${_TGDB_CORE_DEPS_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_CORE_DEPS_LOADED=1

# 入口最小核心依賴（其他功能依賴由各模組自行處理）
TGDB_ENTRY_CORE_DEPS=(
  "awk"
  "grep"
  "sed"
  "cut"
  "tr"
  "find"
  "xargs"
)

_tgdb_dep_list_missing() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || printf '%s\n' "$cmd"
  done
}

_tgdb_dep_join_list() {
  local IFS='、'
  printf '%s' "$*"
}

_tgdb_dep_core_pkg_for_cmd() {
  local cmd="$1"
  case "$cmd" in
    awk) echo "gawk" ;;
    grep) echo "grep" ;;
    sed) echo "sed" ;;
    cut|tr) echo "coreutils" ;;
    find|xargs) echo "findutils" ;;
    *) echo "" ;;
  esac
}

_tgdb_dep_collect_core_packages() {
  declare -A seen=()
  local cmd pkg
  for cmd in "$@"; do
    pkg="$(_tgdb_dep_core_pkg_for_cmd "$cmd")"
    [ -n "$pkg" ] || continue
    if [ -z "${seen[$pkg]+x}" ]; then
      seen["$pkg"]=1
      printf '%s\n' "$pkg"
    fi
  done
}

tgdb_check_entry_dependencies() {
  if [ "${TGDB_SKIP_DEP_CHECK:-0}" = "1" ]; then
    return 0
  fi

  if [ "${_TGDB_ENTRY_DEP_CHECK_DONE:-0}" = "1" ]; then
    return 0
  fi
  _TGDB_ENTRY_DEP_CHECK_DONE=1

  local -a missing_core=()
  local -a install_packages=()
  mapfile -t missing_core < <(_tgdb_dep_list_missing "${TGDB_ENTRY_CORE_DEPS[@]}")
  if [ ${#missing_core[@]} -eq 0 ]; then
    return 0
  fi

  if ! pkg_has_supported_manager; then
    tgdb_fail "缺少核心依賴：$(_tgdb_dep_join_list "${missing_core[@]}")，且無法識別套件管理器，請手動安裝後重試。" 1 || true
    return 1
  fi

  if ! require_root; then
    tgdb_fail "缺少核心依賴：$(_tgdb_dep_join_list "${missing_core[@]}")，且無法取得 root/sudo 權限進行自動安裝。" 1 || true
    return 1
  fi

  mapfile -t install_packages < <(_tgdb_dep_collect_core_packages "${missing_core[@]}")
  if [ ${#install_packages[@]} -eq 0 ]; then
    install_packages=("coreutils" "findutils" "grep" "sed" "gawk")
  fi

  echo "⚙️ 偵測缺少核心依賴：$(_tgdb_dep_join_list "${missing_core[@]}")"
  echo "⏳ 正在自動安裝核心套件：$(_tgdb_dep_join_list "${install_packages[@]}")"

  if ! install_package "${install_packages[@]}"; then
    tgdb_fail "核心依賴自動安裝失敗，請手動安裝後重試。" 1 || true
    return 1
  fi

  mapfile -t missing_core < <(_tgdb_dep_list_missing "${TGDB_ENTRY_CORE_DEPS[@]}")
  if [ ${#missing_core[@]} -gt 0 ]; then
    tgdb_fail "安裝後仍缺少核心依賴：$(_tgdb_dep_join_list "${missing_core[@]}")，請手動補齊後重試。" 1 || true
    return 1
  fi

  echo "✅ 核心依賴已補齊。"
  return 0
}
