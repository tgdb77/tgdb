#!/bin/bash

# TGDB systemd / journal 觀測模組
# 注意：此檔案會被 source，請勿在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_SYSTEMD_OBSERVE_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_SYSTEMD_OBSERVE_LOADED=1

# shellcheck source=src/core/bootstrap.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_DIR/core/quadlet_common.sh"
# shellcheck source=src/podman/common.sh
source "$SRC_DIR/podman/common.sh"
# shellcheck source=src/podman/quadlet_units.sh
source "$SRC_DIR/podman/quadlet_units.sh"

TGDB_OBSERVE_MENU_INDEXES=()
TGDB_OBSERVE_USER_SCOPE_READY=1
TGDB_OBSERVE_JOURNAL_READY=1
TGDB_OBSERVE_LAST_COLLECT_ERROR=""

# 以顯示編號作為索引，方便互動選單直接選取。
TGDB_OBSERVE_SCOPE=()
TGDB_OBSERVE_KIND=()
TGDB_OBSERVE_SERVICE_KEY=()
TGDB_OBSERVE_UNIT_NAME=()
TGDB_OBSERVE_SOURCE_PATH=()
TGDB_OBSERVE_ACTIVE_STATE=()
TGDB_OBSERVE_SUB_STATE=()
TGDB_OBSERVE_UNIT_FILE_STATE=()
TGDB_OBSERVE_DESCRIPTION=()
TGDB_OBSERVE_LOAD_STATE=()
TGDB_OBSERVE_FRAGMENT_PATH=()
TGDB_OBSERVE_FAILED_MARK=()


tgdb_observe_require_systemd_tools() {
  if ! command -v systemctl >/dev/null 2>&1; then
    tgdb_fail "本功能目前僅支援 systemd 系統。" 1 || return $?
  fi
  return 0
}

tgdb_observe_has_journalctl() {
  command -v journalctl >/dev/null 2>&1
}

tgdb_observe_systemctl_read() {
  local scope="${1:-user}"
  shift || true

  scope="$(tgdb_normalize_scope "$scope" 2>/dev/null || printf '%s\n' user)"
  case "$scope" in
    user)
      systemctl --user "$@"
      ;;
    system)
      if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
        systemctl "$@"
      elif command -v sudo >/dev/null 2>&1; then
        sudo systemctl "$@"
      else
        systemctl "$@"
      fi
      ;;
  esac
}

tgdb_observe_systemctl_mutate() {
  local scope="${1:-user}"
  shift || true

  scope="$(tgdb_normalize_scope "$scope" 2>/dev/null || printf '%s\n' user)"
  case "$scope" in
    user)
      systemctl --user "$@"
      ;;
    system)
      if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
        systemctl "$@"
      elif command -v sudo >/dev/null 2>&1; then
        sudo systemctl "$@"
      else
        tgdb_fail "缺少 sudo，無法操作 system scope 單元：$*" 1 || return $?
      fi
      ;;
  esac
}

tgdb_observe_journalctl() {
  local scope="${1:-user}"
  shift || true

  scope="$(tgdb_normalize_scope "$scope" 2>/dev/null || printf '%s\n' user)"
  case "$scope" in
    user)
      journalctl --user -q "$@"
      ;;
    system)
      if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
        journalctl -q "$@"
      elif command -v sudo >/dev/null 2>&1; then
        sudo journalctl -q "$@"
      else
        journalctl -q "$@"
      fi
      ;;
  esac
}

tgdb_observe_user_scope_available() {
  tgdb_observe_systemctl_read user list-unit-files --type=service --no-pager >/dev/null 2>&1
}

tgdb_observe_reset_menu_state() {
  TGDB_OBSERVE_MENU_INDEXES=()
  TGDB_OBSERVE_LAST_COLLECT_ERROR=""

  TGDB_OBSERVE_SCOPE=()
  TGDB_OBSERVE_KIND=()
  TGDB_OBSERVE_SERVICE_KEY=()
  TGDB_OBSERVE_UNIT_NAME=()
  TGDB_OBSERVE_SOURCE_PATH=()
  TGDB_OBSERVE_ACTIVE_STATE=()
  TGDB_OBSERVE_SUB_STATE=()
  TGDB_OBSERVE_UNIT_FILE_STATE=()
  TGDB_OBSERVE_DESCRIPTION=()
  TGDB_OBSERVE_LOAD_STATE=()
  TGDB_OBSERVE_FRAGMENT_PATH=()
  TGDB_OBSERVE_FAILED_MARK=()
}

tgdb_observe_kind_from_unit() {
  local unit="$1"
  case "$unit" in
    *.timer) printf '%s\n' "timer" ;;
    *.service) printf '%s\n' "service" ;;
    *.socket) printf '%s\n' "socket" ;;
    *.path) printf '%s\n' "path" ;;
    *) printf '%s\n' "other" ;;
  esac
}

tgdb_observe_kind_from_quadlet() {
  local filename="$1"
  case "$filename" in
    *.container) printf '%s\n' "container" ;;
    *.pod) printf '%s\n' "pod" ;;
    *.network) printf '%s\n' "network" ;;
    *.volume) printf '%s\n' "volume" ;;
    *.image) printf '%s\n' "image" ;;
    *.device) printf '%s\n' "device" ;;
    *.kube) printf '%s\n' "kube" ;;
    *) tgdb_observe_kind_from_unit "$filename" ;;
  esac
}

tgdb_observe_first_resolved_unit() {
  local scope="$1" token="$2"
  local candidate
  local fallback=""

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    case "$candidate" in
      *.service|*.timer|*.socket|*.path)
        if [ -z "$fallback" ]; then
          fallback="$candidate"
        fi
        if tgdb_observe_systemctl_read "$scope" cat -- "$candidate" >/dev/null 2>&1; then
          printf '%s\n' "$candidate"
          return 0
        fi
        ;;
    esac
  done < <(_resolve_unit_candidates "$token" 2>/dev/null || true)

  if [ -n "$fallback" ]; then
    printf '%s\n' "$fallback"
    return 0
  fi

  printf '%s\n' "$token"
  return 0
}

tgdb_observe_emit_unit_record() {
  local scope="$1" kind="$2" service_key="$3" unit_name="$4" source_path="$5"
  printf '%s\t%s\t%s\t%s\t%s\n' "$scope" "$kind" "$service_key" "$unit_name" "$source_path"
}

tgdb_observe_emit_named_unit_if_exists() {
  local scope="$1" unit_name="$2" kind="$3" service_key="$4"
  local load_state=""

  load_state="$(tgdb_observe_systemctl_read "$scope" show --property=LoadState --value -- "$unit_name" 2>/dev/null || true)"
  case "$load_state" in
    loaded|masked|error|bad-setting)
      tgdb_observe_emit_unit_record "$scope" "$kind" "$service_key" "$unit_name" ""
      return 0
      ;;
  esac

  if tgdb_observe_systemctl_read "$scope" cat -- "$unit_name" >/dev/null 2>&1; then
    tgdb_observe_emit_unit_record "$scope" "$kind" "$service_key" "$unit_name" ""
  fi
}

tgdb_observe_local_systemd_unit_path() {
  local scope="$1" unit_name="$2"
  scope="$(tgdb_normalize_scope "$scope" 2>/dev/null || printf '%s\n' user)"
  case "$scope" in
    system)
      if declare -F rm_system_systemd_dir >/dev/null 2>&1; then
        printf '%s/%s\n' "$(rm_system_systemd_dir)" "$unit_name"
      else
        printf '/etc/systemd/system/%s\n' "$unit_name"
      fi
      ;;
    *)
      printf '%s/%s\n' "$(rm_user_systemd_dir 2>/dev/null || printf '%s\n' "$HOME/.config/systemd/user")" "$unit_name"
      ;;
  esac
}

tgdb_observe_emit_podman_auto_update_unit_if_relevant() {
  local scope="$1" unit_name="$2" kind="$3"
  local local_path active_state unit_file_state

  local_path="$(tgdb_observe_local_systemd_unit_path "$scope" "$unit_name")"
  if [ -e "$local_path" ] || [ -L "$local_path" ]; then
    tgdb_observe_emit_unit_record "$scope" "$kind" "podman-auto-update" "$unit_name" "$local_path"
    return 0
  fi

  active_state="$(tgdb_observe_systemctl_read "$scope" show --property=ActiveState --value -- "$unit_name" 2>/dev/null || true)"
  unit_file_state="$(tgdb_observe_systemctl_read "$scope" show --property=UnitFileState --value -- "$unit_name" 2>/dev/null || true)"

  case "$active_state" in
    active|activating|deactivating|failed)
      tgdb_observe_emit_unit_record "$scope" "$kind" "podman-auto-update" "$unit_name" ""
      return 0
      ;;
  esac
  case "$unit_file_state" in
    enabled|enabled-runtime|linked|linked-runtime|masked|bad|generated)
      tgdb_observe_emit_unit_record "$scope" "$kind" "podman-auto-update" "$unit_name" ""
      return 0
      ;;
  esac
}

tgdb_observe_service_key_from_name() {
  local name="$1"
  name="${name##*/}"
  name="${name#tgdb-}"
  name="${name%.service}"
  name="${name%.timer}"
  name="${name%.socket}"
  name="${name%.path}"
  name="${name%.container}"
  name="${name%.pod}"
  name="${name%.network}"
  name="${name%.volume}"
  name="${name%.image}"
  name="${name%.device}"
  name="${name%.kube}"
  printf '%s\n' "$name"
}

tgdb_observe_is_known_advanced_user_unit() {
  local base="$1"
  case "$base" in
    tgdb-rclone-*.service|tgdb-rclone-*.timer|tgdb-rclone-*.path|tgdb-rclone-*.socket)
      return 0
      ;;
    nginx.service|container-nginx.service)
      return 0
      ;;
    cloudflared-*.service|container-cloudflared-*.service)
      return 0
      ;;
    headscale*.service|container-headscale*.service|pod-headscale*.service)
      return 0
      ;;
    kopia*.service|gameserver*.service|container-gameserver*.service)
      return 0
      ;;
  esac
  return 1
}

tgdb_observe_user_unit_is_managed() {
  local path="$1"
  local base="${path##*/}"
  local tgdb_root="${TGDB_DIR:-}"
  local persist_root="${PERSIST_CONFIG_DIR:-}"

  case "$base" in
    tgdb-*|*.mount)
      return 0
      ;;
  esac

  if tgdb_observe_is_known_advanced_user_unit "$base"; then
    return 0
  fi

  if [ -n "$tgdb_root" ] && grep -Fq -- "$tgdb_root" "$path" 2>/dev/null; then
    return 0
  fi
  if [ -n "$persist_root" ] && grep -Fq -- "$persist_root" "$path" 2>/dev/null; then
    return 0
  fi
  if grep -Eq '/(\.tgdb|var/lib/tgdb)/' "$path" 2>/dev/null; then
    return 0
  fi

  return 1
}

tgdb_observe_collect_quadlet_units_by_mode() {
  local mode="$1"
  local scope service base path unit_name kind service_key

  while IFS=$'\t' read -r scope service base path _; do
    [ -n "${scope:-}" ] || continue
    [ -n "${base:-}" ] || continue
    unit_name="$(tgdb_observe_first_resolved_unit "$scope" "$base" 2>/dev/null || printf '%s\n' "$base")"
    kind="$(tgdb_observe_kind_from_quadlet "$base")"
    service_key="${service:-$(tgdb_observe_service_key_from_name "$unit_name")}"
    tgdb_observe_emit_unit_record "$scope" "$kind" "$service_key" "$unit_name" "$path"
  done < <(rm_list_tgdb_runtime_quadlet_files_by_mode "$mode" 2>/dev/null || true)
}

tgdb_observe_collect_user_systemd_units() {
  local dir path base service_key kind
  dir="$(rm_user_systemd_dir 2>/dev/null || true)"
  [ -d "$dir" ] || return 0

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ! tgdb_observe_user_unit_is_managed "$path"; then
      continue
    fi
    base="${path##*/}"
    kind="$(tgdb_observe_kind_from_unit "$base")"
    service_key="$(tgdb_observe_service_key_from_name "$base")"
    tgdb_observe_emit_unit_record "user" "$kind" "$service_key" "$base" "$path"
  done < <(find "$dir" -maxdepth 1 \( -type f -o -type l \) \
    \( -name '*.service' -o -name '*.timer' -o -name '*.socket' -o -name '*.path' \) \
    -print 2>/dev/null | LC_ALL=C sort)
}

tgdb_observe_collect_extra_named_units() {
  # 額外納入：
  # - podman-auto-update：僅在已啟用、正在執行、失敗或 TGDB 建立了本機單元檔時納入；
  #   避免停用並移除本機單元後，仍因 Podman 套件內建單元而出現在清單。
  # - tailscale：屬於進階應用 / Headscale 相關依賴，常為 system scope 的 tailscaled.service
  # - tmux：若系統上真的有 tmux.service / tmux.socket，也一併列入觀測
  tgdb_observe_emit_podman_auto_update_unit_if_relevant user "podman-auto-update.timer" "timer"
  tgdb_observe_emit_podman_auto_update_unit_if_relevant user "podman-auto-update.service" "service"
  tgdb_observe_emit_podman_auto_update_unit_if_relevant system "podman-auto-update.timer" "timer"
  tgdb_observe_emit_podman_auto_update_unit_if_relevant system "podman-auto-update.service" "service"

  tgdb_observe_emit_named_unit_if_exists system "tailscaled.service" "service" "tailscale"
  tgdb_observe_emit_named_unit_if_exists system "tailscaled.socket" "socket" "tailscale"

  tgdb_observe_emit_named_unit_if_exists user "tmux.service" "service" "tmux"
  tgdb_observe_emit_named_unit_if_exists user "tmux.socket" "socket" "tmux"
  tgdb_observe_emit_named_unit_if_exists system "tmux.service" "service" "tmux"
  tgdb_observe_emit_named_unit_if_exists system "tmux.socket" "socket" "tmux"
}

tgdb_observe_collect_all_units() {
  {
    tgdb_observe_collect_quadlet_units_by_mode rootless
    tgdb_observe_collect_quadlet_units_by_mode rootful
    tgdb_observe_collect_user_systemd_units
    tgdb_observe_collect_extra_named_units
  } | awk -F'\t' 'NF>=5 && !seen[$1 FS $4 FS $5]++'
}

tgdb_observe_fetch_unit_metadata() {
  local scope="$1" unit="$2"
  local line
  local active="unknown" sub="unknown" unit_file="unknown" desc=""
  local load="unknown" fragment=""

  while IFS= read -r line; do
    case "$line" in
      ActiveState=*) active="${line#ActiveState=}" ;;
      SubState=*) sub="${line#SubState=}" ;;
      UnitFileState=*) unit_file="${line#UnitFileState=}" ;;
      Description=*) desc="${line#Description=}" ;;
      LoadState=*) load="${line#LoadState=}" ;;
      FragmentPath=*) fragment="${line#FragmentPath=}" ;;
    esac
  done < <(tgdb_observe_systemctl_read "$scope" show \
    --property=ActiveState \
    --property=SubState \
    --property=UnitFileState \
    --property=Description \
    --property=LoadState \
    --property=FragmentPath \
    -- "$unit" 2>/dev/null || true)

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$active" "$sub" "$unit_file" "$desc" "$load" "$fragment"
}

tgdb_observe_is_failed_state() {
  local active="$1" sub="$2" load="$3"
  case "$active" in
    failed) return 0 ;;
  esac
  case "$sub" in
    failed|dead-failed) return 0 ;;
  esac
  case "$load" in
    error|not-found|bad-setting|masked) return 0 ;;
  esac
  return 1
}

tgdb_observe_store_menu_record() {
  local idx="$1" scope="$2" kind="$3" service_key="$4" unit_name="$5" source_path="$6"
  local active="$7" sub="$8" unit_file="$9" desc="${10}" load="${11}" fragment="${12}" failed_mark="${13}"

  TGDB_OBSERVE_MENU_INDEXES+=("$idx")
  TGDB_OBSERVE_SCOPE[$idx]="$scope"
  TGDB_OBSERVE_KIND[$idx]="$kind"
  TGDB_OBSERVE_SERVICE_KEY[$idx]="$service_key"
  TGDB_OBSERVE_UNIT_NAME[$idx]="$unit_name"
  TGDB_OBSERVE_SOURCE_PATH[$idx]="$source_path"
  TGDB_OBSERVE_ACTIVE_STATE[$idx]="$active"
  TGDB_OBSERVE_SUB_STATE[$idx]="$sub"
  TGDB_OBSERVE_UNIT_FILE_STATE[$idx]="$unit_file"
  TGDB_OBSERVE_DESCRIPTION[$idx]="$desc"
  TGDB_OBSERVE_LOAD_STATE[$idx]="$load"
  TGDB_OBSERVE_FRAGMENT_PATH[$idx]="$fragment"
  TGDB_OBSERVE_FAILED_MARK[$idx]="$failed_mark"

}

tgdb_observe_refresh_menu_cache() {
  local scope kind service_key unit_name source_path
  local meta active sub unit_file desc load fragment
  local normal_idx=1 failed_idx=101 failed_mark

  tgdb_observe_reset_menu_state
  TGDB_OBSERVE_USER_SCOPE_READY=1
  TGDB_OBSERVE_JOURNAL_READY=1
  tgdb_observe_has_journalctl || TGDB_OBSERVE_JOURNAL_READY=0
  tgdb_observe_user_scope_available || TGDB_OBSERVE_USER_SCOPE_READY=0

  while IFS=$'\t' read -r scope kind service_key unit_name source_path; do
    [ -n "${scope:-}" ] || continue
    [ -n "${unit_name:-}" ] || continue

    meta="$(tgdb_observe_fetch_unit_metadata "$scope" "$unit_name")"
    IFS=$'\t' read -r active sub unit_file desc load fragment <<< "$meta"

    failed_mark=0
    if tgdb_observe_is_failed_state "$active" "$sub" "$load"; then
      failed_mark=1
      tgdb_observe_store_menu_record "$failed_idx" "$scope" "$kind" "$service_key" "$unit_name" "$source_path" "$active" "$sub" "$unit_file" "$desc" "$load" "$fragment" "$failed_mark"
      failed_idx=$((failed_idx + 1))
    else
      tgdb_observe_store_menu_record "$normal_idx" "$scope" "$kind" "$service_key" "$unit_name" "$source_path" "$active" "$sub" "$unit_file" "$desc" "$load" "$fragment" "$failed_mark"
      normal_idx=$((normal_idx + 1))
    fi
  done < <(tgdb_observe_collect_all_units | LC_ALL=C sort -t$'\t' -k4,4 -k1,1)

  if [ ${#TGDB_OBSERVE_MENU_INDEXES[@]} -eq 0 ]; then
    TGDB_OBSERVE_LAST_COLLECT_ERROR="目前找不到 TGDB 管理的 systemd / Quadlet 單元。"
  fi
}

tgdb_observe_print_unit_line() {
  local idx="$1"
  printf ' %3s. %-32s %-7s %-9s %-10s\n' \
    "$idx" \
    "${TGDB_OBSERVE_UNIT_NAME[$idx]}" \
    "${TGDB_OBSERVE_SCOPE[$idx]}" \
    "${TGDB_OBSERVE_ACTIVE_STATE[$idx]}" \
    "${TGDB_OBSERVE_UNIT_FILE_STATE[$idx]}"
}

tgdb_observe_print_units_block() {
  local want_failed="$1"
  local idx
  local printed=0

  for idx in "${TGDB_OBSERVE_MENU_INDEXES[@]}"; do
    if [ "${TGDB_OBSERVE_FAILED_MARK[$idx]:-0}" != "$want_failed" ]; then
      continue
    fi
    tgdb_observe_print_unit_line "$idx"
    printed=1
  done

  if [ "$printed" -eq 0 ]; then
    echo "  （無）"
  fi
}

tgdb_observe_print_menu_screen() {
  clear
  print_header "服務觀測（systemd / logs）"
  echo "[正常服務]"
  tgdb_observe_print_units_block 0
  echo "----------------------------------"
  echo "[異常 / failed 服務]"
  tgdb_observe_print_units_block 1
  echo "----------------------------------"
  echo "1. 查看服務狀態詳情"
  echo "2. 查看服務日誌"
  echo "3. 即時追蹤服務日誌"
  echo "4. 重新啟動服務後查看最後 50 行日誌"
  echo "----------------------------------"
  echo "0. 返回"
  echo "=================================="


  if [ -n "$TGDB_OBSERVE_LAST_COLLECT_ERROR" ]; then
    echo
    tgdb_warn "$TGDB_OBSERVE_LAST_COLLECT_ERROR"
  fi
  if [ "$TGDB_OBSERVE_USER_SCOPE_READY" -ne 1 ]; then
    echo
    tgdb_warn "目前無法讀取 systemd --user 狀態，user scope 單元可能顯示 unknown。"
  fi
  if [ "$TGDB_OBSERVE_JOURNAL_READY" -ne 1 ]; then
    echo
    tgdb_warn "系統未提供 journalctl，日誌相關功能將不可用。"
  fi
}

tgdb_observe_prompt_menu_action() {
  local __out_var="$1"
  local choice=""
  while true; do
    read -r -e -p "請輸入功能 [0-4]: " choice
    case "$choice" in
      0|1|2|3|4)
        printf -v "$__out_var" '%s' "$choice"
        return 0
        ;;
      *)
        tgdb_err "請輸入 0-4。"
        ;;
    esac
  done
}

tgdb_observe_prompt_unit_index() {
  local __out_var="$1"
  local prompt="$2"
  local value=""

  if [ ${#TGDB_OBSERVE_MENU_INDEXES[@]} -eq 0 ]; then
    tgdb_err "目前沒有可操作的單元。"
    return 1
  fi

  while true; do
    read -r -e -p "$prompt" value
    case "$value" in
      0)
        return 2
        ;;
      "")
        tgdb_err "請輸入服務編號。"
        ;;
      *)
        if [[ "$value" =~ ^[0-9]+$ ]] && [ -n "${TGDB_OBSERVE_UNIT_NAME[$value]:-}" ]; then
          printf -v "$__out_var" '%s' "$value"
          return 0
        fi
        tgdb_err "找不到對應的服務編號：$value"
        ;;
    esac
  done
}

tgdb_observe_show_timer_summary() {
  local scope="$1" unit="$2"
  local line last_trigger="" next_elapse="" triggers=""

  while IFS= read -r line; do
    case "$line" in
      LastTriggerUSec=*) last_trigger="${line#LastTriggerUSec=}" ;;
      NextElapseUSecRealtime=*) next_elapse="${line#NextElapseUSecRealtime=}" ;;
      Triggers=*) triggers="${line#Triggers=}" ;;
    esac
  done < <(tgdb_observe_systemctl_read "$scope" show \
    --property=LastTriggerUSec \
    --property=NextElapseUSecRealtime \
    --property=Triggers \
    -- "$unit" 2>/dev/null || true)

  echo "Timer 排程："
  echo "- 上次執行：${last_trigger:-n/a}"
  echo "- 下次執行：${next_elapse:-n/a}"
  echo "- 觸發服務：${triggers:-n/a}"
}

tgdb_observe_print_unit_detail() {
  local idx="$1"
  local scope="${TGDB_OBSERVE_SCOPE[$idx]}"
  local unit="${TGDB_OBSERVE_UNIT_NAME[$idx]}"
  local kind="${TGDB_OBSERVE_KIND[$idx]}"
  local service_key="${TGDB_OBSERVE_SERVICE_KEY[$idx]}"
  local source_path="${TGDB_OBSERVE_SOURCE_PATH[$idx]}"
  local status_output=""

  clear
  print_header "服務狀態詳情"
  echo "服務：${service_key:-$unit}"
  echo "Scope：$scope"
  echo "Unit：$unit"
  echo "類型：$kind"
  echo "狀態：${TGDB_OBSERVE_ACTIVE_STATE[$idx]} (${TGDB_OBSERVE_SUB_STATE[$idx]})"
  echo "開機啟用：${TGDB_OBSERVE_UNIT_FILE_STATE[$idx]}"
  echo "LoadState：${TGDB_OBSERVE_LOAD_STATE[$idx]}"
  echo "來源：${source_path:-n/a}"
  echo "Description：${TGDB_OBSERVE_DESCRIPTION[$idx]:-(無)}"
  echo "FragmentPath：${TGDB_OBSERVE_FRAGMENT_PATH[$idx]:-(無)}"
  if [ "$kind" = "timer" ]; then
    echo
    tgdb_observe_show_timer_summary "$scope" "$unit"
  fi

  echo
  echo "systemctl status 摘要："
  echo "----------------------------------"
  status_output="$(tgdb_observe_systemctl_read "$scope" status --no-pager --lines=20 -- "$unit" 2>&1 || true)"
  if [ -n "$status_output" ]; then
    printf '%s\n' "$status_output"
  else
    tgdb_warn "無法讀取 $unit 的 status。"
  fi

  ui_pause "按任意鍵返回..."
}

tgdb_observe_show_recent_logs() {
  local idx="$1"
  local scope="${TGDB_OBSERVE_SCOPE[$idx]}"
  local unit="${TGDB_OBSERVE_UNIT_NAME[$idx]}"

  if [ "$TGDB_OBSERVE_JOURNAL_READY" -ne 1 ]; then
    tgdb_warn "系統未提供 journalctl。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  clear
  print_header "服務日誌：$unit"
  tgdb_observe_journalctl "$scope" -u "$unit" --no-pager || tgdb_warn "無法讀取 $unit 的 journal。"
  ui_pause "按任意鍵返回..."
  return 0
}

tgdb_observe_follow_logs() {
  local idx="$1"
  local scope="${TGDB_OBSERVE_SCOPE[$idx]}"
  local unit="${TGDB_OBSERVE_UNIT_NAME[$idx]}"

  if [ "$TGDB_OBSERVE_JOURNAL_READY" -ne 1 ]; then
    tgdb_warn "系統未提供 journalctl。"
    ui_pause "按任意鍵返回..."
    return 1
  fi
  if ! ui_is_interactive; then
    tgdb_warn "即時追蹤僅支援互動式終端。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  clear
  print_header "即時追蹤：$unit"
  echo "按 Ctrl+C 可停止追蹤並返回。"
  echo "----------------------------------"

  local pid="" rc=0
  local old_trap_int old_trap_term
  old_trap_int="$(trap -p INT 2>/dev/null || true)"
  old_trap_term="$(trap -p TERM 2>/dev/null || true)"

  tgdb_observe_journalctl "$scope" -u "$unit" -f -n 50 &
  pid=$!

  # 讓 Ctrl+C 只停止 journalctl -f，避免中斷整個 TGDB 主程式。
  trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' INT TERM
  wait "$pid" || rc=$?

  if [ -n "$old_trap_int" ]; then
    eval "$old_trap_int"
  else
    trap - INT
  fi
  if [ -n "$old_trap_term" ]; then
    eval "$old_trap_term"
  else
    trap - TERM
  fi

  echo
  case "$rc" in
    0|130|143)
      return 0
      ;;
    *)
      tgdb_warn "無法追蹤 $unit 的 journal。"
      ui_pause "按任意鍵返回..."
      return 1
      ;;
  esac
}

tgdb_observe_restart_and_tail() {
  local idx="$1"
  local scope="${TGDB_OBSERVE_SCOPE[$idx]}"
  local unit="${TGDB_OBSERVE_UNIT_NAME[$idx]}"

  if ! ui_confirm_yn "確定要重新啟動 $unit 嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
    return 0
  fi

  clear
  print_header "重新啟動：$unit"
  if ! tgdb_observe_systemctl_mutate "$scope" restart -- "$unit"; then
    tgdb_warn "重新啟動 $unit 失敗。"
    ui_pause "按任意鍵返回..."
    return 1
  fi

  echo "✅ 已送出重新啟動：$unit"
  echo
  echo "最後 50 行日誌："
  echo "----------------------------------"
  if [ "$TGDB_OBSERVE_JOURNAL_READY" -ne 1 ]; then
    tgdb_warn "系統未提供 journalctl。"
  elif ! tgdb_observe_journalctl "$scope" -u "$unit" -n 50 --no-pager; then
    tgdb_warn "無法讀取 $unit 的 journal。"
  fi
  ui_pause "按任意鍵返回..."
}

tgdb_observe_menu_dispatch() {
  local action="$1"
  local idx=""
  local rc=0

  tgdb_observe_prompt_unit_index idx "請輸入服務編號（輸入 0 取消）: "
  rc=$?
  case "$rc" in
    0) ;;
    2) return 0 ;;
    *) ui_pause "按任意鍵返回..."; return 1 ;;
  esac

  case "$action" in
    1) tgdb_observe_print_unit_detail "$idx" ;;
    2) tgdb_observe_show_recent_logs "$idx" ;;
    3) tgdb_observe_follow_logs "$idx" ;;
    4) tgdb_observe_restart_and_tail "$idx" ;;
  esac
}

systemd_observe_menu() {
  local action=""

  tgdb_observe_require_systemd_tools || {
    ui_pause "按任意鍵返回..."
    return 1
  }

  while true; do
    tgdb_observe_refresh_menu_cache
    tgdb_observe_print_menu_screen

    if ! tgdb_observe_prompt_menu_action action; then
      ui_pause "按任意鍵返回..."
      continue
    fi

    case "$action" in
      0)
        return 0
        ;;
      1|2|3|4)
        tgdb_observe_menu_dispatch "$action" || true
        ;;
    esac
  done
}
