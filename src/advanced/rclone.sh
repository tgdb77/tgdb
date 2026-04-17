#!/bin/bash

# Rclone 管理模組

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SRC_ROOT/core/bootstrap.sh"
# shellcheck source=src/core/quadlet_common.sh
source "$SRC_ROOT/core/quadlet_common.sh"

RCLONE_CONFIG_FILE_DEFAULT="$TGDB_DIR/rclone.conf"
RCLONE_CUSTOM_DIR="$TGDB_DIR/rclone"
RCLONE_COMMANDS_FILE="$RCLONE_CUSTOM_DIR/commands.list"
RCLONE_MOUNTS_DIR="$TGDB_DIR/mounts"

RCLONE_REPO_CONFIG_DIR="$CONFIG_DIR/rclone"
RCLONE_REPO_MOUNT_ARGS_FILE="$RCLONE_REPO_CONFIG_DIR/mount.args"
RCLONE_CUSTOM_MOUNT_ARGS_FILE="$RCLONE_CUSTOM_DIR/mount.args"

__RCLONE_BIN="rclone"

__RCLONE_MOUNT_HELP_CACHE=""

_ensure_rclone_mount_args_file() {
  ensure_paths

  if [ -f "$RCLONE_CUSTOM_MOUNT_ARGS_FILE" ]; then
    return 0
  fi

  if [ -f "$RCLONE_REPO_MOUNT_ARGS_FILE" ]; then
    cp -n "$RCLONE_REPO_MOUNT_ARGS_FILE" "$RCLONE_CUSTOM_MOUNT_ARGS_FILE" 2>/dev/null || true
  fi
  return 0
}

_rclone_mount_args_contains() {
  local needle="${1:-}"; shift || true
  [ -n "$needle" ] || return 1
  local a
  for a in "$@"; do
    [ "$a" = "$needle" ] && return 0
  done
  return 1
}

load_rclone_mount_args() {
  _ensure_rclone_mount_args_file || true

  local file=""
  if [ -f "$RCLONE_CUSTOM_MOUNT_ARGS_FILE" ]; then
    file="$RCLONE_CUSTOM_MOUNT_ARGS_FILE"
  elif [ -f "$RCLONE_REPO_MOUNT_ARGS_FILE" ]; then
    file="$RCLONE_REPO_MOUNT_ARGS_FILE"
  fi

  RCLONE_MOUNT_ARGS=()
  if [ -n "$file" ] && [ -f "$file" ]; then
    local line
    while IFS= read -r line || [ -n "$line" ]; do
      line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      case "$line" in
        \#*) continue ;;
      esac
      # shellcheck disable=SC2206
      local parts=($line)
      RCLONE_MOUNT_ARGS+=("${parts[@]}")
    done < "$file"
  fi

  if [ ${#RCLONE_MOUNT_ARGS[@]} -eq 0 ]; then
    RCLONE_MOUNT_ARGS=(
      "--vfs-cache-mode" "full"
      "--buffer-size" "128M"
      "--vfs-read-chunk-size" "16M"
      "--vfs-read-chunk-size-limit" "521M"
      "--vfs-read-chunk-streams" "4"
      "--vfs-cache-max-size" "15G"
      "--vfs-cache-max-age" "12h"
      "--dir-cache-time" "12h"
      "--retries" "5"
      "--allow-other"
    )
  fi
}

ensure_paths() {
    mkdir -p "$RCLONE_CUSTOM_DIR"
    mkdir -p "$RCLONE_MOUNTS_DIR"
}

ensure_rclone_config_env() {
    ensure_paths

    if [ -z "${RCLONE_CONFIG:-}" ]; then
        export RCLONE_CONFIG="$RCLONE_CONFIG_FILE_DEFAULT"
    fi

    if [ ! -f "$RCLONE_CONFIG" ]; then
        touch "$RCLONE_CONFIG"
        chmod 600 "$RCLONE_CONFIG" 2>/dev/null || true
    fi
}

apply_rclone_env_runtime() {
    export RCLONE_CONFIG="$RCLONE_CONFIG_FILE_DEFAULT"

    # 讓後續以 systemd --user 啟動的服務可讀到最新變數（支援環境會自動略過失敗）
    _systemctl_user_try import-environment RCLONE_CONFIG >/dev/null 2>&1 || true
}

# 非互動設定 RCLONE_CONFIG 並寫入 ~/.bashrc（整合到安裝流程使用）
set_rclone_env_noninteractive() {
    ensure_paths
    apply_rclone_env_runtime
    if [ ! -f "$RCLONE_CONFIG" ]; then
        touch "$RCLONE_CONFIG"
    fi
    chmod 600 "$RCLONE_CONFIG" 2>/dev/null || true
    if [ -f "$HOME/.bashrc" ]; then
        sed -i '/^export RCLONE_CONFIG=/d' "$HOME/.bashrc"
    fi
    echo "export RCLONE_CONFIG=\"$RCLONE_CONFIG_FILE_DEFAULT\"" >> "$HOME/.bashrc"
    echo "✅ 已設定 RCLONE_CONFIG=$RCLONE_CONFIG_FILE_DEFAULT，並同步到目前流程與 ~/.bashrc"
}

# 確保 /etc/fuse.conf 啟用 user_allow_other（需要 root 權限）
ensure_user_allow_other() {
    if [ ! -f /etc/fuse.conf ]; then
        echo "正在建立 /etc/fuse.conf 並啟用 user_allow_other ..."
        sudo sh -lc 'echo user_allow_other > /etc/fuse.conf' || {
            tgdb_fail "無法寫入 /etc/fuse.conf" 1 || true
            return 1
        }
        return 0
    fi
    if grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null; then
        return 0
    fi
    echo "正在啟用 /etc/fuse.conf 的 user_allow_other ..."
    sudo sh -lc 'echo user_allow_other >> /etc/fuse.conf' || {
        tgdb_fail "無法修改 /etc/fuse.conf" 1 || true
        return 1
    }
}

# 準備 systemd 使用者單元環境
ensure_systemd_user_ready() {
    if ! command -v systemctl >/dev/null 2>&1; then
        return 1
    fi
    mkdir -p "$HOME/.config/systemd/user"
    sudo loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    return 0
}

check_network_for_installer() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "未找到 curl，正在安裝 curl..."
        install_package curl || return 1
    fi
    return 0
}

install_or_update_rclone() {
  clear
  echo "=================================="
  echo "❖ 安裝/更新 rclone（特供版）❖"
  echo "=================================="
  echo "本功能將使用：curl -sSL instl.vercel.app/rclone |sudo bash"
  echo "並安裝/更新 fuse3 以支援掛載"
  echo "設定檔位置變更至 $TGDB_DIR"
  echo "----------------------------------"

  local auto_confirm=${TGDB_CLI_MODE:-0}
  if [ "$auto_confirm" != "1" ]; then
    if ! ui_confirm_yn "確認繼續嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      echo "操作已取消"
      ui_pause
      return
    fi
  fi

  if ! check_network_for_installer; then
    [ "$auto_confirm" = "1" ] || ui_pause
    return 1
  fi

  local install_cmd="curl -sSL instl.vercel.app/rclone |sudo bash"
  if [ "$auto_confirm" = "1" ]; then
    install_cmd="curl -sSL instl.vercel.app/rclone |sudo bash"
  fi

  if bash -lc "$install_cmd"; then
    echo "✅ rclone 安裝/更新完成"
  else
    tgdb_fail "rclone 安裝/更新失敗，請至 https://github.com/tgdrive/rclone 手動下載" 1 || true
    [ "$auto_confirm" = "1" ] || ui_pause
    return 1
  fi

  echo "正在安裝/更新 fuse3..."
  if install_package fuse3; then
    echo "✅ fuse3 安裝/更新完成"
  else
    tgdb_warn "自動安裝 fuse3 失敗，嘗試安裝 fuse..."
    install_package fuse || true
  fi

  # 直接啟用 user_allow_other
  ensure_user_allow_other || true

  # 設定 RCLONE_CONFIG 並寫入 ~/.bashrc
  set_rclone_env_noninteractive
  echo "ℹ️ 目前 TGDB 流程已可直接使用新的 RCLONE_CONFIG。"
  echo "ℹ️ 若你要在外層 shell 立即使用，請執行：source ~/.bashrc"
  echo "        已在 /etc/fuse.conf 啟用 user_allow_other，" >&2
  echo "        這代表同一台機器上的其他系統使用者，理論上可透過 FUSE 掛載點讀取資料。" >&2
  echo "        建議僅在『單一使用者』的 VPS 或你完全信任本機使用者的環境啟用。" >&2

  if [ "$auto_confirm" != "1" ]; then
    ui_pause
  fi
}

remove_rclone() {
  local auto_confirm=${TGDB_CLI_MODE:-0}

  clear
  echo "=================================="
  echo "❖ 移除 rclone ❖"
  echo "=================================="

  local rclone_path
  rclone_path=$(command -v rclone 2>/dev/null || true)
  if [ -n "$rclone_path" ]; then
    echo "偵測到 rclone 執行檔：$rclone_path"
  else
    echo "目前系統未偵測到 rclone 執行檔（可能原本就未安裝）。"
  fi
  echo "本操作將嘗試："
  echo "  - 透過套件管理器移除 rclone（若有安裝套件）"
  echo "  - 如仍存在執行檔，可選擇直接刪除該檔案"
  echo "  - 可選擇是否一併刪除 TGDB 專用設定檔：$RCLONE_CONFIG_FILE_DEFAULT"
  echo "----------------------------------"

  if [ "$auto_confirm" != "1" ]; then
    if ! ui_confirm_yn "確認要移除 rclone 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      echo "操作已取消"
      ui_pause
      return 0
    fi
  fi

  if ! require_root; then
    [ "$auto_confirm" = "1" ] || ui_pause
    return 1
  fi

  echo "正在透過套件管理器嘗試移除 rclone（如適用）..."
  pkg_purge "rclone" || true
  pkg_autoremove || true

  rclone_path=$(command -v rclone 2>/dev/null || true)
  if [ -n "$rclone_path" ]; then
    local rm_confirm="y"
    if [ "$auto_confirm" != "1" ]; then
      if ui_confirm_yn "系統仍偵測到 rclone 執行檔，是否直接刪除此檔案？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        rm_confirm="y"
      else
        rm_confirm="n"
      fi
    fi
    if [[ "$rm_confirm" =~ ^[Yy]$ ]]; then
      sudo rm -f "$rclone_path" 2>/dev/null || true
      if ! command -v rclone >/dev/null 2>&1; then
        echo "✅ 已刪除 rclone 執行檔。"
      else
        tgdb_warn "嘗試刪除 rclone 執行檔失敗，請手動檢查。"
      fi
    else
      echo "已保留 rclone 執行檔：$rclone_path"
    fi
  else
    echo "✅ 系統目前未偵測到 rclone 執行檔。"
  fi

  local cfg_confirm="y"
  if [ -f "$RCLONE_CONFIG_FILE_DEFAULT" ]; then
    if [ "$auto_confirm" != "1" ]; then
      if ui_confirm_yn "是否一併移除 rclone 設定檔 $RCLONE_CONFIG_FILE_DEFAULT？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        cfg_confirm="y"
      else
        cfg_confirm="n"
      fi
    fi
    if [[ "$cfg_confirm" =~ ^[Yy]$ ]]; then
      rm -f "$RCLONE_CONFIG_FILE_DEFAULT" 2>/dev/null || true
      echo "✅ 已刪除 rclone 設定檔：$RCLONE_CONFIG_FILE_DEFAULT"
    else
      echo "已保留 rclone 設定檔：$RCLONE_CONFIG_FILE_DEFAULT"
    fi
  else
    echo "ℹ️ 未偵測到 TGDB 專用 rclone 設定檔：$RCLONE_CONFIG_FILE_DEFAULT"
  fi

  if [ "$auto_confirm" != "1" ]; then
    ui_pause
  fi
}

add_remote_storage() {
    local auto_confirm=${TGDB_CLI_MODE:-0}
    clear
    echo "=================================="
    echo "❖ 新增遠端儲存 ❖"
    echo "=================================="
    if [ ! -t 0 ]; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi
    ensure_rclone_config_env
    echo "將開啟 rclone 互動式設定。設定檔：$RCLONE_CONFIG"
    echo "完成後可用 'rclone listremotes' 檢視遠端清單。"
    echo "----------------------------------"
    read -r -e -p "按 Enter 開始，或輸入 q 取消: " go
    if [[ "$go" =~ ^[Qq]$ ]]; then
        return
    fi
    "$__RCLONE_BIN" config --config "$RCLONE_CONFIG"
    chmod 600 "$RCLONE_CONFIG" 2>/dev/null || true
    [ "$auto_confirm" = "1" ] || ui_pause
}

edit_rclone_conf() {
    clear
    echo "=================================="
    echo "❖ 編輯 rclone.conf ❖"
    echo "=================================="
    ensure_rclone_config_env
    local editor_cmd
    editor_cmd="${EDITOR:-nano}"
    if ! command -v "$editor_cmd" >/dev/null 2>&1; then
        echo "未找到 $editor_cmd，嘗試安裝 nano..."
        if ! install_package nano; then
            tgdb_fail "無法安裝 nano" 1 || true
            if [ "${TGDB_CLI_MODE:-0}" != "1" ]; then
                ui_pause
            fi
            return 1
        fi
        editor_cmd="nano"
    fi
    echo "設定檔：$RCLONE_CONFIG"
    "$editor_cmd" "$RCLONE_CONFIG"
    chmod 600 "$RCLONE_CONFIG" 2>/dev/null || true
}

list_remotes() {
    ensure_rclone_config_env
    "$__RCLONE_BIN" listremotes --config "$RCLONE_CONFIG" 2>/dev/null | sed 's/:$//' | sed '/^$/d'
}

mount_remote_storage() {
    clear
    echo "=================================="
    echo "❖ 掛載遠端儲存 ❖"
    echo "=================================="
    ensure_rclone_config_env
    load_rclone_mount_args

    local remotes
    remotes=$(list_remotes)
    if [ -z "$remotes" ]; then
        echo "尚未設定任何遠端。"
        if ui_confirm_yn "是否立即新增遠端？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            add_remote_storage
        fi
        return
    fi

    echo "可用遠端："
    local i=1
    local arr=()
    while IFS= read -r r; do
        [ -z "$r" ] && continue
        echo "$i. $r"
        arr+=("$r")
        i=$((i+1))
    done <<EOF
${remotes}
EOF

    echo "----------------------------------"
    echo "0. 返回"
    local idx
    if ! ui_prompt_index idx "請選擇遠端編號 [0-${#arr[@]}]: " 1 "${#arr[@]}" "" 0; then
        return
    fi
    local remote_name="${arr[$((idx-1))]}"

    read -r -e -p "請輸入要掛載的遠端路徑（預設 ${remote_name}:/）: " remote_path
    if [ -z "$remote_path" ]; then
        remote_path="${remote_name}:"
    fi

    local default_mount_point="$RCLONE_MOUNTS_DIR/${remote_name}"
    read -r -e -p "請輸入掛載點（預設 $default_mount_point）: " mount_point
    mount_point=${mount_point:-$default_mount_point}
    mkdir -p "$mount_point"

    local common_args=(
        "--config" "$RCLONE_CONFIG"
        "${RCLONE_MOUNT_ARGS[@]}"
    )

    echo ""
    echo "即將建立並啟動 systemd 使用者服務以掛載："
    echo "$remote_path -> $mount_point"

    if _rclone_mount_args_contains "--allow-other" "${common_args[@]}"; then
      ensure_user_allow_other || true
    fi

    if ensure_systemd_user_ready; then
        local user_unit_dir="$HOME/.config/systemd/user"
        local key_str="$remote_path::$mount_point"
        local slug
        slug=$(echo "$key_str" | tr -c 'A-Za-z0-9' '-' | tr -s '-' | sed 's/^-//; s/-$//' | tr '[:upper:]' '[:lower:]')
        local service_name="tgdb-rclone-${slug}.service"
        local service_file="$user_unit_dir/$service_name"

        local rclone_bin
        rclone_bin=$(command -v rclone || echo rclone)

        local args_line=""
        for a in "${common_args[@]}"; do
            args_line="$args_line $(printf '%q' "$a")"
        done

        cat > "$service_file" <<EOF
[Unit]
Description=TGDB Rclone Mount $remote_path to $mount_point
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=RCLONE_CONFIG=$RCLONE_CONFIG
ExecStartPre=/usr/bin/env mkdir -p "$mount_point"
ExecStart=$rclone_bin mount "$remote_path" "$mount_point"$args_line
ExecStop=/usr/bin/env sh -c 'fusermount3 -u "\$1" 2>/dev/null || fusermount -u "\$1" 2>/dev/null || umount -l "\$1" 2>/dev/null || true' -- "$mount_point"
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

        _systemctl_user_try daemon-reload || true
        _systemctl_user_try enable --now -- "$service_name" && {
            echo "✅ 已透過 systemd 啟動並設定開機自動掛載：$mount_point"
            ui_pause
            return
        }
        tgdb_warn "systemd 使用者服務啟動失敗，將改用背景掛載。"
    fi

    local mount_cmd=(rclone mount "$remote_path" "$mount_point" "${common_args[@]}")
    local mount_cmd_str=""
    local a
    for a in "${mount_cmd[@]}"; do
        mount_cmd_str+=$(printf '%q ' "$a")
    done
    nohup bash -lc "setsid ${mount_cmd_str} --daemon 2>/dev/null" >/dev/null 2>&1 || \
        nohup "${mount_cmd[@]}" >/dev/null 2>&1 &

    sleep 1
    if mount | grep -q "on $mount_point type fuse.rclone"; then
        echo "✅ 掛載成功：$mount_point"
    else
        tgdb_warn "已嘗試掛載。若未成功，請檢查 rclone 與 fuse3 是否正常。"
    fi
    if [ "${TGDB_CLI_MODE:-0}" != "1" ]; then
        ui_pause
    fi
}

unmount_remote_storage() {
    clear
    echo "=================================="
    echo "❖ 卸載遠端儲存 ❖"
    echo "=================================="

    local entries=()
    if [ -d "$RCLONE_MOUNTS_DIR" ]; then
        while IFS= read -r -d $'\0' mp; do
            if mount | grep -q "on $mp type fuse.rclone"; then
                entries+=("$mp")
            fi
        done < <(find "$RCLONE_MOUNTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    while IFS= read -r line; do
        local mp
        mp=$(echo "$line" | awk '{print $3}')
        [ -n "$mp" ] && entries+=("$mp")
    done < <(mount | grep ' type fuse.rclone ' || true)

    mapfile -t entries < <(printf "%s\n" "${entries[@]}" | awk 'NF' | sort -u)

    if [ ${#entries[@]} -eq 0 ]; then
        echo "未找到任何 rclone 掛載。"
        ui_pause
        return
    fi

    echo "當前掛載點："
    local i=1
    for mp in "${entries[@]}"; do
        echo "$i. $mp"
        i=$((i+1))
    done
    echo "----------------------------------"
    echo "0. 返回"
    local idx
    if ! ui_prompt_index idx "請選擇要卸載的編號 [0-${#entries[@]}]: " 1 "${#entries[@]}" "" 0; then
        return
    fi
    local target_mp="${entries[$((idx-1))]}"

    echo "正在卸載：$target_mp"

    local user_unit_dir="$HOME/.config/systemd/user"
    if [ -d "$user_unit_dir" ]; then
        local svc_path
        svc_path=$(grep -rl --fixed-strings "$target_mp" "$user_unit_dir"/tgdb-rclone-*.service 2>/dev/null | head -n1 || true)
        if [ -n "$svc_path" ]; then
            local svc_name
            svc_name="$(basename "$svc_path")"
            _systemctl_user_try stop -- "$svc_name" || true
            _systemctl_user_try disable --now -- "$svc_name" || true
        fi
    fi
    if command -v fusermount3 >/dev/null 2>&1; then
        fusermount3 -u "$target_mp" 2>/dev/null || fusermount3 -uz "$target_mp" 2>/dev/null || true
    elif command -v fusermount >/dev/null 2>&1; then
        fusermount -u "$target_mp" 2>/dev/null || fusermount -uz "$target_mp" 2>/dev/null || true
    fi
    umount "$target_mp" 2>/dev/null || umount -l "$target_mp" 2>/dev/null || true

    sleep 1
    if mount | grep -q "on $target_mp type fuse.rclone"; then
        tgdb_fail "卸載失敗，請檢查是否仍有程序占用。" 1 || true
    else
        echo "✅ 已卸載：$target_mp"
    fi
    if [ "${TGDB_CLI_MODE:-0}" != "1" ]; then
        ui_pause
    fi
}

rclone_mount_cli() {
    local remote="$1" mount_point="$2"
    if [ -z "$remote" ] || [ -z "$mount_point" ]; then
        tgdb_fail "需要 <remote> <mount_point>" 1 || true
        return 1
    fi
    ensure_rclone_config_env
    load_rclone_mount_args
    local found="false"
    while IFS= read -r r; do
        [ "$r" = "$remote" ] && found="true"
    done < <(list_remotes)
    if [ "$found" != "true" ]; then
        tgdb_fail "找不到遠端：$remote" 1 || true
        return 1
    fi

    mkdir -p "$mount_point"

    local remote_path="${remote}:"
    local common_args=(
        "--config" "$RCLONE_CONFIG"
        "${RCLONE_MOUNT_ARGS[@]}"
    )

    if _rclone_mount_args_contains "--allow-other" "${common_args[@]}"; then
      ensure_user_allow_other || true
    fi

    local mount_cmd=(rclone mount "$remote_path" "$mount_point" "${common_args[@]}")
    local mount_cmd_str=""
    local a
    for a in "${mount_cmd[@]}"; do
        mount_cmd_str+=$(printf '%q ' "$a")
    done
    nohup bash -lc "setsid ${mount_cmd_str} --daemon 2>/dev/null" >/dev/null 2>&1 || \
        nohup "${mount_cmd[@]}" >/dev/null 2>&1 &

    sleep 1
    if mount | grep -q "on $mount_point type fuse.rclone"; then
        echo "✅ 掛載成功：$mount_point"
    else
        tgdb_warn "已嘗試掛載。若未成功，請檢查 rclone 與 fuse3 是否正常。"
        return 1
    fi
}

rclone_unmount_cli() {
    local mount_point="$1"
    if [ -z "$mount_point" ]; then
        tgdb_fail "需要 <mount_point>" 1 || true
        return 1
    fi
    local ok=false
    if mount | grep -q "on $mount_point type fuse.rclone"; then
        fusermount3 -u "$mount_point" 2>/dev/null && ok=true
        fusermount -u "$mount_point" 2>/dev/null && ok=true
        umount -l "$mount_point" 2>/dev/null && ok=true
    fi
    if [ "$ok" = true ]; then
        echo "✅ 已卸載：$mount_point"
    else
        tgdb_warn "找不到掛載或卸載可能失敗：$mount_point"
        return 1
    fi
}

show_mounts() {
    clear
    echo "=================================="
    echo "❖ rclone 掛載狀態 ❖"
    echo "=================================="
    mount | grep ' type fuse.rclone ' || echo "無 rclone 掛載"
    echo "----------------------------------"
    ui_pause
}

# 自訂義指令管理
custom_commands_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    ensure_paths
    touch "$RCLONE_COMMANDS_FILE"

    while true; do
        clear
        echo "=================================="
        echo "❖ 自訂義指令 ❖"
        echo "=================================="
        if [ -s "$RCLONE_COMMANDS_FILE" ]; then
            echo "已儲存指令："
            nl -ba "$RCLONE_COMMANDS_FILE" | sed 's/|/ - /'
        else
            echo "已儲存指令：無資料"
        fi
        echo "----------------------------------"
        echo "1. 新增儲存指令"
        echo "2. 從已儲存清單執行"
        echo "3. 個別刪除"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-3]: " cc

        case "$cc" in
            1)
                add_and_run_custom_command
                ;;
            2)
                run_saved_custom_command
                ;;
            3)
                if [ ! -s "$RCLONE_COMMANDS_FILE" ]; then
                    echo "無資料"
                    ui_pause
                    continue
                fi
                nl -ba "$RCLONE_COMMANDS_FILE"
                read -r -e -p "輸入要刪除的行號: " ln
                if [[ "$ln" =~ ^[0-9]+$ ]]; then
                    sed -i "${ln}d" "$RCLONE_COMMANDS_FILE"
                    echo "✅ 已刪除第 $ln 行"
                else
                    tgdb_err "無效行號"
                fi
                ui_pause
                ;;
            0)
                return
                ;;
            *)
                echo "無效選項"
                sleep 1
                ;;
        esac
    done
}

add_and_run_custom_command() {
    ensure_rclone_config_env
    ensure_paths
    touch "$RCLONE_COMMANDS_FILE"

    local name cmd
    read -r -e -p "請為此命令命名（可使用中文；不可包含 |）: " name
    if ! _rclone_custom_name_valid "$name"; then
        tgdb_err "$(_rclone_custom_name_msg)"
        sleep 1; return
    fi

    read -r -e -p "請輸入要儲存的命令（不會立即執行）: " cmd
    if [ -z "$cmd" ]; then
        tgdb_err "命令不能為空"
        sleep 1; return
    fi

    _rclone_custom_save_named_command "$name" "$cmd"
    echo "✅ 已新增並儲存為：$name（未執行）"
    ui_pause
}

run_saved_custom_command() {
    ensure_paths
    if [ ! -s "$RCLONE_COMMANDS_FILE" ]; then
        echo "尚無儲存的指令"
        ui_pause
        return
    fi

    mapfile -t lines < "$RCLONE_COMMANDS_FILE"
    clear
    echo "已儲存指令："
    local i=1
    for line in "${lines[@]}"; do
        local name cmd
        name="${line%%|*}"
        cmd="${line#*|}"
        echo "$i. $name - $cmd"
        i=$((i+1))
    done
    echo "----------------------------------"
    echo "0. 返回"
    local idx
    if ! ui_prompt_index idx "請選擇要執行的編號 [0-${#lines[@]}]: " 1 "${#lines[@]}" "" 0; then
        return
    fi
    local line="${lines[$((idx-1))]}"
    local name cmd
    name="${line%%|*}"; cmd="${line#*|}"
    echo "即將執行 [$name]: $cmd"
    if ui_confirm_yn "確認執行？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        bash -lc "$cmd"
    else
        echo "已取消執行"
    fi
    ui_pause
}

# 驗證自訂指令名稱（允許中文；不可為空、不可含分隔符號 | 或換行）
_rclone_custom_name_valid() {
    local name="${1:-}"
    [ -n "$name" ] || return 1
    case "$name" in
        *"|"*|*$'\n'*|*$'\r'*) return 1 ;;
    esac
    return 0
}

_rclone_custom_name_msg() {
    echo "名稱不合法（可使用中文；不可為空，且不能包含 | 或換行）"
}

_rclone_custom_save_named_command() {
    local name="$1"
    local cmd="$2"

    ensure_paths
    touch "$RCLONE_COMMANDS_FILE"

    awk -F'|' -v name="$name" '$1 != name { print }' "$RCLONE_COMMANDS_FILE" > "$RCLONE_COMMANDS_FILE.tmp" 2>/dev/null || true
    mv "$RCLONE_COMMANDS_FILE.tmp" "$RCLONE_COMMANDS_FILE" 2>/dev/null || true
    printf '%s|%s\n' "$name" "$cmd" >> "$RCLONE_COMMANDS_FILE"
}

_rclone_custom_has_name() {
    local name="$1"
    [ -s "$RCLONE_COMMANDS_FILE" ] || return 1

    awk -F'|' -v name="$name" '
      BEGIN { found=0 }
      $1 == name { found=1; exit }
      END { exit(found ? 0 : 1) }
    ' "$RCLONE_COMMANDS_FILE"
}

_rclone_custom_get_line_by_name() {
    local name="$1"
    [ -s "$RCLONE_COMMANDS_FILE" ] || return 1

    awk -F'|' -v name="$name" '
      $1 == name { line=$0 }
      END {
        if (line != "") {
          print line
          exit 0
        }
        exit 1
      }
    ' "$RCLONE_COMMANDS_FILE"
}

_rclone_custom_delete_by_name() {
    local name="$1"
    [ -s "$RCLONE_COMMANDS_FILE" ] || return 1

    awk -F'|' -v name="$name" '$1 != name { print }' "$RCLONE_COMMANDS_FILE" > "$RCLONE_COMMANDS_FILE.tmp" 2>/dev/null || true
    mv "$RCLONE_COMMANDS_FILE.tmp" "$RCLONE_COMMANDS_FILE" 2>/dev/null || true
}

# ---- CLI 專用：自訂義指令 ----
rclone_custom_add_cli() {
    local name="$1"; shift
    local cmd="$*"

    if ! _rclone_custom_name_valid "$name"; then
        tgdb_fail "$(_rclone_custom_name_msg)：$name" 2 || true
        return 2
    fi
    if [ -z "$cmd" ]; then
        tgdb_fail "命令內容不能為空" 2 || true
        return 2
    fi

    _rclone_custom_save_named_command "$name" "$cmd"
    echo "✅ 已新增並儲存指令名稱：$name（未執行）"
}

rclone_custom_run_saved_cli() {
    local name="$1"; shift

    ensure_rclone_config_env
    ensure_paths

    if ! _rclone_custom_name_valid "$name"; then
        tgdb_fail "$(_rclone_custom_name_msg)：$name" 2 || true
        return 2
    fi

    if [ ! -s "$RCLONE_COMMANDS_FILE" ]; then
        echo "無資料"
        return 1
    fi

    if ! _rclone_custom_has_name "$name"; then
        tgdb_fail "找不到指定名稱：$name" 1 || true
        return 1
    fi

    local line cmd cmd_to_run arg
    line=$(_rclone_custom_get_line_by_name "$name")
    cmd="${line#*|}"
    cmd_to_run="$cmd"

    for arg in "$@"; do
        cmd_to_run+=" $(printf '%q' "$arg")"
    done

    echo "即將執行 [$name]: $cmd_to_run"
    bash -lc "$cmd_to_run"
}

rclone_show_mounts_cli() {
    echo "=================================="
    echo "❖ rclone 掛載狀態 ❖"
    echo "=================================="
    if mount 2>/dev/null | grep ' type fuse.rclone ' >/dev/null 2>&1; then
        mount 2>/dev/null | grep ' type fuse.rclone ' || true
    else
        echo "無 rclone 掛載"
    fi
}

rclone_custom_list_cli() {
    ensure_paths
    if [ -s "$RCLONE_COMMANDS_FILE" ]; then
        nl -ba "$RCLONE_COMMANDS_FILE"
    else
        echo "無資料"
    fi
}

rclone_custom_delete_cli() {
    local name="$1"
    ensure_paths

    if ! _rclone_custom_name_valid "$name"; then
        tgdb_fail "$(_rclone_custom_name_msg)：$name" 2 || true
        return 2
    fi

    if [ ! -s "$RCLONE_COMMANDS_FILE" ]; then
        echo "無資料，無法刪除：$name"
        return 1
    fi
    if ! _rclone_custom_has_name "$name"; then
        tgdb_fail "找不到指定名稱：$name" 1 || true
        return 1
    fi

    _rclone_custom_delete_by_name "$name"
    echo "✅ 已刪除已儲存指令：$name"
}

# 取得 rclone 安裝狀態與版本（避免未安裝時菜單中斷）
check_rclone_status() {
  local rclone_installed="false"
  local rclone_version=""

  if command -v "$__RCLONE_BIN" >/dev/null 2>&1; then
    rclone_installed="true"
    rclone_version=$(
      "$__RCLONE_BIN" version 2>/dev/null | head -n1 | awk '{print $2}' | sed 's/^v//' || true
    )
  fi

  printf "%s,%s\n" "$rclone_installed" "${rclone_version:-unknown}"
}

_print_rclone_overview_inline() {
  local status rclone_installed rclone_version

  status=$(check_rclone_status)
  rclone_installed=$(echo "$status" | cut -d',' -f1)
  rclone_version=$(echo "$status" | cut -d',' -f2)

  if [ "$rclone_installed" = "true" ]; then
    if [ -n "$rclone_version" ] && [ "$rclone_version" != "unknown" ]; then
      echo "[Rclone: 已安裝 ✅ (v$rclone_version)]"
    else
      echo "[Rclone: 已安裝 ✅]"
    fi
  else
    echo "[Rclone: 未安裝 ❌]"
  fi
}

# 主選單
rclone_menu() {
  if ! ui_is_interactive; then
    tgdb_fail "Rclone 管理需要互動式終端（TTY）。" 2 || true
    return 2
  fi

  while true; do
    clear
    echo "=================================="
    echo "❖ Rclone 管理 ❖"
    echo "教學與文件：https://rclone.org/docs/"
    _print_rclone_overview_inline
    echo "=================================="
    echo "1. 安裝/更新 rclone（含 fuse3）"
    echo "2. 新增遠端儲存"
    echo "3. 編輯 rclone.conf"
    echo "4. 掛載遠端儲存"
    echo "5. 卸載遠端儲存"
    echo "6. 查看掛載狀態"
    echo "7. 自訂義指令"
    echo "----------------------------------"
    echo "d. 移除 rclone"
    echo "----------------------------------"
    echo "0. 返回主選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-8]: " choice

    case "$choice" in
      1)
        install_or_update_rclone
        ;;
      2)
        add_remote_storage
        ;;
      3)
        edit_rclone_conf
        ;;
      4)
        mount_remote_storage
        ;;
      5)
        unmount_remote_storage
        ;;
      6)
        show_mounts
        ;;
      7)
        custom_commands_menu
        ;;
      d)
        remove_rclone
        ;;
      0)
        return
        ;;
      *)
        echo "無效選項，請重新輸入。"
        sleep 1
        ;;
    esac
  done
}
