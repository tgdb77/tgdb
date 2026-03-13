#!/bin/bash

# Game Server：部署流程
# 注意：此檔案為 library，會被 source；請勿在此更改 shell options。

_gameserver_prompt_shortname() {
  local out_var="$1"
  local input_shortname=""

  echo "請先查詢官方 shortname 對照表："
  _gameserver_shortname_url
  echo "----------------------------------"

  while true; do
    read -r -e -p "請輸入要部署的遊戲代號 shortname（例：cs2、rust、mc，輸入 0 取消）: " input_shortname
    if [ "$input_shortname" = "0" ]; then
      return 2
    fi

    input_shortname="${input_shortname,,}"
    if _gameserver_is_valid_shortname "$input_shortname"; then
      printf -v "$out_var" '%s' "$input_shortname"
      return 0
    fi

    tgdb_err "shortname 格式不正確：僅允許小寫英數與連字號（-）。"
  done
}

_gameserver_prompt_instance_name() {
  local shortname="$1" out_var="$2"
  local default_name input chosen_instance_name unit_base

  default_name="$(_gameserver_next_default_instance_name "$shortname")"

  while true; do
    read -r -e -p "請輸入實例名稱（預設：${default_name}，輸入 0 取消）: " input
    if [ "$input" = "0" ]; then
      return 2
    fi

    chosen_instance_name="${input:-$default_name}"
    chosen_instance_name="${chosen_instance_name,,}"
    if ! _gameserver_is_valid_instance_name "$chosen_instance_name"; then
      tgdb_err "實例名稱格式不正確：僅允許小寫英數、.、_、-。"
      continue
    fi

    unit_base="$(_gameserver_unit_base_from_instance_name "$chosen_instance_name")"
    if _gameserver_instance_exists "$unit_base"; then
      tgdb_err "已存在同名實例（$chosen_instance_name），請更換名稱。"
      continue
    fi

    printf -v "$out_var" '%s' "$chosen_instance_name"
    return 0
  done
}

_gameserver_default_volume_dir() {
  local unit_base="$1"
  local backup_root

  if declare -F tgdb_backup_root >/dev/null 2>&1; then
    backup_root="$(tgdb_backup_root)"
  else
    backup_root="${TGDB_BACKUP_ROOT:-$(dirname "${TGDB_DIR:-$HOME/.tgdb/app}")}"
  fi

  printf '%s\n' "$backup_root/volume/gameserver/$unit_base"
}

_gameserver_prompt_volume_dir() {
  local unit_base="$1" out_var="$2"
  local default_volume input chosen_volume_dir

  default_volume="$(_gameserver_default_volume_dir "$unit_base")"

  while true; do
    read -r -e -p "請輸入資料目錄（預設 0=自動建立 ${default_volume}）: " input
    input="${input:-0}"

    if [ "$input" = "0" ]; then
      if declare -F ensure_app_volume_dir >/dev/null 2>&1; then
        chosen_volume_dir="$(ensure_app_volume_dir "gameserver" "$unit_base")" || return 1
      else
        chosen_volume_dir="$default_volume"
        mkdir -p "$chosen_volume_dir" 2>/dev/null || {
          tgdb_fail "無法建立資料目錄：$chosen_volume_dir" 1 || true
          return 1
        }
      fi
      printf -v "$out_var" '%s' "$chosen_volume_dir"
      return 0
    fi

    chosen_volume_dir="$input"
    if printf '%s' "$chosen_volume_dir" | grep -q '[[:space:]]' 2>/dev/null; then
      tgdb_err "路徑不可包含空白字元，請改用不含空白的路徑。"
      continue
    fi

    if [ -e "$chosen_volume_dir" ] && [ ! -d "$chosen_volume_dir" ]; then
      tgdb_err "$chosen_volume_dir 不是資料夾，請重新輸入。"
      continue
    fi

    if [ ! -d "$chosen_volume_dir" ]; then
      if ! mkdir -p "$chosen_volume_dir" 2>/dev/null; then
        tgdb_err "無法建立資料夾：$chosen_volume_dir（請確認權限）。"
        continue
      fi
    fi

    if [ ! -r "$chosen_volume_dir" ] || [ ! -w "$chosen_volume_dir" ]; then
      tgdb_err "目前使用者對 $chosen_volume_dir 沒有讀寫權限，請調整權限後再試。"
      continue
    fi

    printf -v "$out_var" '%s' "$chosen_volume_dir"
    return 0
  done
}

_gameserver_render_quadlet_content() {
  local unit_base="$1" image="$2" instance_dir="$3" volume_dir="$4"
  local tpl content

  tpl="$(_gameserver_repo_quadlet_template)"
  if [ ! -f "$tpl" ]; then
    tgdb_fail "找不到 Game Server Quadlet 樣板：$tpl" 1 || true
    return 1
  fi

  content="$(cat "$tpl")"
  content="$(printf '%s' "$content" | sed \
    -e "s|\\\${container_name}|$(_esc "$(_gameserver_container_name_from_unit_base "$unit_base")")|g" \
    -e "s|\\\${image}|$(_esc "$image")|g" \
    -e "s|\\\${instance_dir}|$(_esc "$instance_dir")|g" \
    -e "s|\\\${volume_dir}|$(_esc "$volume_dir")|g" \
  )"

  printf '%s' "$content"
  return 0
}

_gameserver_print_deploy_success() {
  local unit_base="$1" shortname="$2" image="$3" instance_dir="$4" volume_dir="$5"

  echo "✅ 已完成部署：$unit_base，下載伺服器中利用日誌功能察看進度"
  echo "--------------------------------------------------"
  echo "shortname : $shortname"
  echo "image     : $image"
  echo "instance  : $instance_dir（備份輸出目錄）"
  echo "volume    : $volume_dir"
  echo "--------------------------------------------------"
  echo "目前使用 host 網路模式，請務必留意："
  echo "1) 使用LinuxGSM 維運命令 details 查看伺服器實際使用埠。"
  echo "2) 編輯單元改為 bridge 並啟用對應 PublishPort。"
  echo "3) 記得開放對應防火牆埠（TCP/UDP 依遊戲需求）。"
  echo "--------------------------------------------------"
  echo "可使用下列流程調整："
  echo "  進階應用 -> Game Server（LinuxGSM） -> 維運命令 details"
  echo "  主選單 -> 5. Podman 管理 -> 編輯現有單元"
  echo "--------------------------------------------------"
}

gameserver_p_deploy() {
  _gameserver_require_tty || return $?
  _gameserver_require_podman || { ui_pause "按任意鍵返回..."; return 1; }
  _gameserver_require_supported_arch || { ui_pause "按任意鍵返回..."; return 1; }

  _gameserver_ensure_records_layout

  local shortname instance_name unit_base container_name image instance_dir volume_dir unit_content

  echo "=================================="
  echo "❖ 新增/部署 Game Server（LinuxGSM）❖"
  echo "=================================="

  _gameserver_prompt_shortname shortname || {
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "操作已取消。"
      return 0
    fi
    return "$rc"
  }

  _gameserver_prompt_instance_name "$shortname" instance_name || {
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "操作已取消。"
      return 0
    fi
    return "$rc"
  }

  unit_base="$(_gameserver_unit_base_from_instance_name "$instance_name")"
  container_name="$(_gameserver_container_name_from_unit_base "$unit_base")"
  image="ghcr.io/gameservermanagers/gameserver:${shortname}"
  instance_dir="$(_gameserver_instance_dir "$unit_base")"

  _gameserver_prompt_volume_dir "$unit_base" volume_dir || return $?

  mkdir -p "$instance_dir" 2>/dev/null || {
    tgdb_fail "無法建立實例目錄：$instance_dir" 1 || true
    return 1
  }

  unit_content="$(_gameserver_render_quadlet_content "$unit_base" "$image" "$instance_dir" "$volume_dir")" || return $?

  _install_unit_and_enable "$unit_base" "$unit_content" || {
    tgdb_fail "套用 Quadlet 失敗：$unit_base" 1 || true
    return 1
  }

  _gameserver_write_instance_metadata "$instance_name" "$unit_base" "$container_name" "$shortname" "$image" "$instance_dir" "$volume_dir"
  _gameserver_write_record_quadlet "$unit_base" "$unit_content"

  _gameserver_print_deploy_success "$unit_base" "$shortname" "$image" "$instance_dir" "$volume_dir"
  ui_pause "按任意鍵返回..."
  return 0
}
