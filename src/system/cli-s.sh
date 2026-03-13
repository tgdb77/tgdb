#!/bin/bash

# 系統管理：CLI（內部用）
# 說明：提供 env_setup 等流程以 CLI 模式呼叫的「無互動、預設值」操作。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

system_admin_cli_require_internal() {
  if [ "${TGDB_INTERNAL:-0}" != "1" ]; then
    tgdb_fail "此 CLI 功能為內部使用，暫不對外開放。" 3 || true
    return 3
  fi
  return 0
}

system_admin_cli_swap_default() {
  system_admin_cli_require_internal || return $?
  if ! declare -F virtual_memory_apply_swap_size >/dev/null 2>&1; then
    tgdb_fail "缺少函式 virtual_memory_apply_swap_size，請確認已載入 src/system/virtual_memory.sh" 1 || true
    return 1
  fi
  virtual_memory_apply_swap_size "1G"
}

system_admin_cli_timezone_asia_taipei() {
  system_admin_cli_require_internal || return $?
  if ! declare -F timezone_apply >/dev/null 2>&1; then
    tgdb_fail "缺少函式 timezone_apply，請確認已載入 src/system/timezone.sh" 1 || true
    return 1
  fi
  timezone_apply "Asia/Taipei"
}

system_admin_cli_dns_default() {
  system_admin_cli_require_internal || return $?
  if ! declare -F dns_apply_servers >/dev/null 2>&1; then
    tgdb_fail "缺少函式 dns_apply_servers，請確認已載入 src/system/dns.sh" 1 || true
    return 1
  fi
  dns_apply_servers "1.1.1.1" "8.8.8.8"
}

system_admin_cli_enable_bbr_fq() {
  system_admin_cli_require_internal || return $?
  if ! declare -F enable_bbr_fq_cli >/dev/null 2>&1; then
    tgdb_fail "缺少函式 enable_bbr_fq_cli，請確認已載入 src/system/kernel.sh" 1 || true
    return 1
  fi
  enable_bbr_fq_cli
}

system_admin_cli_nftables_init_default() {
  system_admin_cli_require_internal || return $?
  if [ -z "${SRC_DIR:-}" ]; then
    tgdb_fail "SRC_DIR 未設定，無法載入 nftables 模組。" 1 || true
    return 1
  fi
  if [ ! -f "$SRC_DIR/nftables.sh" ]; then
    tgdb_fail "找不到 nftables 模組：$SRC_DIR/nftables.sh" 1 || true
    return 1
  fi
  # shellcheck source=src/nftables.sh
  source "$SRC_DIR/nftables.sh"
  if ! declare -F nftables_init_with_default_cli >/dev/null 2>&1; then
    tgdb_fail "缺少函式 nftables_init_with_default_cli，請確認 src/nftables.sh 已更新。" 1 || true
    return 1
  fi
  nftables_init_with_default_cli
}

system_admin_cli_install_fail2ban_default() {
  system_admin_cli_require_internal || return $?
  if [ -z "${SRC_DIR:-}" ]; then
    tgdb_fail "SRC_DIR 未設定，無法載入 Fail2ban 模組。" 1 || true
    return 1
  fi
  if [ ! -f "$SRC_DIR/fail2ban_manager.sh" ]; then
    tgdb_fail "找不到 Fail2ban 模組：$SRC_DIR/fail2ban_manager.sh" 1 || true
    return 1
  fi
  # shellcheck source=src/fail2ban_manager.sh
  source "$SRC_DIR/fail2ban_manager.sh"
  if ! declare -F install_fail2ban_package_cli >/dev/null 2>&1; then
    tgdb_fail "缺少函式 install_fail2ban_package_cli，請確認 src/fail2ban_manager.sh 已更新。" 1 || true
    return 1
  fi
  install_fail2ban_package_cli
}

system_admin_cli_change_ssh_port_default() {
  system_admin_cli_require_internal || return $?
  if ! declare -F change_ssh_port_cli >/dev/null 2>&1; then
    tgdb_fail "缺少函式 change_ssh_port_cli，請確認已載入 src/system/ssh.sh" 1 || true
    return 1
  fi
  change_ssh_port_cli
}
