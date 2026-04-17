#!/bin/bash

# TGDB Fail2ban 管理
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/core/bootstrap.sh
source "$SCRIPT_DIR/core/bootstrap.sh"

# 常量與預設
F2B_APP_DIR="$TGDB_DIR/fail2ban"
F2B_CONF_ROOT="/etc/fail2ban"
F2B_JAIL_D_DIR="$F2B_CONF_ROOT/jail.d"
F2B_FILTER_D_DIR="$F2B_CONF_ROOT/filter.d"
F2B_ACTION_D_DIR="$F2B_CONF_ROOT/action.d"

F2B_TGDB_SSHD_LOCAL="$F2B_JAIL_D_DIR/tgdb-sshd.local"

# 偵測系統上 Fail2ban 狀態
detect_fail2ban() {
    local active="false"
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet fail2ban; then
        active="true"
    fi
    echo "$active"
}

# 取得配置根目錄
get_fail2ban_conf_root() {
    echo "$F2B_CONF_ROOT"
}

_detect_banaction() {
    # 優先使用 nftables.conf 的 type 參數（Fail2ban 0.11+ 常見），再退回舊的 nftables-multiport
    if command -v nft >/dev/null 2>&1; then
        if [ -f "$F2B_ACTION_D_DIR/nftables.conf" ]; then
            echo "nftables[type=multiport]"
            return 0
        fi
        if [ -f "$F2B_ACTION_D_DIR/nftables-multiport.conf" ]; then
            echo "nftables-multiport"
            return 0
        fi
    fi

    if [ -f "$F2B_ACTION_D_DIR/iptables-multiport.conf" ]; then
        echo "iptables-multiport"
        return 0
    fi

    # 最後退回（避免配置為空導致 Fail2ban 無法啟動）
    echo "iptables-multiport"
}

_detect_sshd_systemd_unit() {
    command -v systemctl >/dev/null 2>&1 || return 1
    if systemctl cat ssh.service >/dev/null 2>&1; then
        echo "ssh.service"
        return 0
    fi
    if systemctl cat sshd.service >/dev/null 2>&1; then
        echo "sshd.service"
        return 0
    fi
    return 1
}

_write_sshd_backend_local_systemd() {
    local unit journalmatch
    unit=$(_detect_sshd_systemd_unit 2>/dev/null || true)
    if [ -n "$unit" ]; then
        journalmatch="_SYSTEMD_UNIT=${unit} + _COMM=sshd"
        sudo tee "$F2B_TGDB_SSHD_LOCAL" >/dev/null <<EOF
[sshd]
backend = systemd
journalmatch = $journalmatch
EOF
        return 0
    fi

    sudo tee "$F2B_TGDB_SSHD_LOCAL" >/dev/null <<EOF
[sshd]
backend = systemd
# 註：若系統的 SSH unit 非 ssh.service/sshd.service，可能需要手動調整 journalmatch。
EOF
}

_write_sshd_backend_local_file() {
    sudo tee "$F2B_TGDB_SSHD_LOCAL" >/dev/null <<EOF
[sshd]
logpath = %(sshd_log)s
backend = auto
EOF
}


# 以系統套件安裝 Fail2ban（最小 SSH 防護，banaction 使用 nftables）
install_fail2ban_package() {
  clear
  echo "=================================="
  echo "❖ 安裝 Fail2ban ❖"
  echo "=================================="
  require_root || { ui_pause; return 1; }

  install_package "fail2ban" || { tgdb_fail "安裝 fail2ban 失敗" 1 || true; ui_pause; return 1; }

  local ssh_port banaction jail_local
  ssh_port=$(detect_ssh_port)
  banaction=$(_detect_banaction)
  jail_local="$F2B_CONF_ROOT/jail.local"

  sudo mkdir -p "$F2B_JAIL_D_DIR"

  if [ -s "$jail_local" ]; then
    tgdb_warn "偵測到已存在配置：$jail_local"
    echo "   TGDB 安裝預設會寫入最小 [DEFAULT]/[sshd] 設定，可能覆蓋你既有自訂。"
    echo "----------------------------------"
    if ! ui_confirm_yn "是否先備份並覆寫 $jail_local？(y/N，輸入 0 取消): " "N"; then
      echo "→ 已保留既有設定，未寫入 TGDB 預設配置。"
      if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable --now fail2ban
        sudo systemctl reload fail2ban 2>/dev/null || true
      fi
      echo "✅ Fail2ban 已安裝並啟用（未變更任何 Fail2ban 配置）"
      ui_pause
      return 0
    fi

    local ts backup
    ts=$(date +%Y%m%d-%H%M%S)
    backup="$F2B_CONF_ROOT/jail.local.tgdb.bak.$ts"
    sudo cp -a "$jail_local" "$backup"
    echo "✅ 已備份原始 jail.local -> $backup"
    echo "----------------------------------"
  fi

  sudo tee "$jail_local" >/dev/null <<EOF
# 由 TGDB 產生：Fail2ban 最小預設設定
[DEFAULT]
banaction = $banaction
backend = auto
ignoreip = 127.0.0.1/8 ::1
findtime = 10m
bantime = 1h
maxretry = 5

[sshd]
enabled = true
port = $ssh_port
EOF

  if [ -f /var/log/auth.log ] || [ -f /var/log/secure ]; then
    _write_sshd_backend_local_file
  elif command -v journalctl >/dev/null 2>&1; then
    _write_sshd_backend_local_systemd
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now fail2ban
    sudo systemctl reload fail2ban 2>/dev/null || true
  fi

  echo "✅ Fail2ban 已安裝並啟用。SSH 埠: $ssh_port，banaction: $banaction"
  ui_pause
}

install_fail2ban_package_cli() {
  echo "=================================="
  echo "❖ 安裝 Fail2ban（CLI）❖"
  echo "=================================="

  require_root || return 1

  install_package "fail2ban" || { tgdb_fail "安裝 fail2ban 失敗" 1 || true; return 1; }

  local ssh_port banaction jail_local
  ssh_port=$(detect_ssh_port)
  banaction=$(_detect_banaction)
  jail_local="$F2B_CONF_ROOT/jail.local"

  sudo mkdir -p "$F2B_JAIL_D_DIR"

  if [ -s "$jail_local" ]; then
    local ts backup
    ts=$(date +%Y%m%d-%H%M%S)
    backup="$F2B_CONF_ROOT/jail.local.tgdb.bak.$ts"
    sudo cp -a "$jail_local" "$backup"
    tgdb_warn "偵測到已存在配置：$jail_local"
    echo "✅ 已自動備份原始 jail.local -> $backup"
    echo "→ 將以 TGDB 預設最小配置覆寫 $jail_local"
  fi

  sudo tee "$jail_local" >/dev/null <<EOF
# 由 TGDB 產生：Fail2ban 最小預設設定
[DEFAULT]
banaction = $banaction
backend = auto
ignoreip = 127.0.0.1/8 ::1
findtime = 10m
bantime = 1h
maxretry = 5

[sshd]
enabled = true
port = $ssh_port
EOF

  if [ -f /var/log/auth.log ] || [ -f /var/log/secure ]; then
    _write_sshd_backend_local_file
  elif command -v journalctl >/dev/null 2>&1; then
    _write_sshd_backend_local_systemd
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now fail2ban
    sudo systemctl reload fail2ban 2>/dev/null || true
  fi

  echo "✅ Fail2ban 已安裝並啟用。SSH 埠: $ssh_port，banaction: $banaction"
  return 0
}

# 更新 Fail2ban（系統套件）
update_fail2ban_package() {
    clear
    echo "=================================="
    echo "❖ 更新 Fail2ban ❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }
    if ! install_package "fail2ban"; then
        tgdb_fail "安裝/更新 fail2ban 失敗，請手動檢查套件管理器狀態。" 1 || true
        ui_pause
        return 1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl restart fail2ban 2>/dev/null || true
    fi
    echo "✅ Fail2ban 已更新"
    ui_pause
}

remove_fail2ban_package() {
    clear
    echo "=================================="
    echo "❖ 移除 Fail2ban ❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl disable --now fail2ban 2>/dev/null || true
    fi
    pkg_purge "fail2ban" || true
    pkg_autoremove || true
    echo "✅ 移除流程已完成（如需保留配置請先行備份）"
    ui_pause
}

# 僅備份 .local 到 $F2B_APP_DIR/fail2ban-local-<timestamp>.tar.gz
backup_fail2ban_local() {
  clear
  echo "=================================="
  echo "❖ 備份 Fail2ban .local ❖"
  echo "=================================="
  require_root || { ui_pause; return 1; }

  mkdir -p "$F2B_APP_DIR"
  local tarball listfile count
  tarball="$F2B_APP_DIR/fail2ban-local-$(date +%Y%m%d-%H%M%S).tar.gz"

  listfile=$(mktemp)
  count=0
  if [ -f "$F2B_CONF_ROOT/jail.local" ]; then
    echo "etc/fail2ban/jail.local" >>"$listfile"
    count=$((count + 1))
  fi
  if [ -d "$F2B_JAIL_D_DIR" ]; then
    while IFS= read -r -d '' f; do
      echo "${f#/}" >>"$listfile"
      count=$((count + 1))
    done < <(find "$F2B_JAIL_D_DIR" -maxdepth 1 -type f -name '*.local' -print0)
  fi
  if [ -d "$F2B_FILTER_D_DIR" ]; then
    while IFS= read -r -d '' f; do
      echo "${f#/}" >>"$listfile"
      count=$((count + 1))
    done < <(find "$F2B_FILTER_D_DIR" -maxdepth 1 -type f -name '*.local' -print0)
  fi
  if [ -d "$F2B_ACTION_D_DIR" ]; then
    while IFS= read -r -d '' f; do
      echo "${f#/}" >>"$listfile"
      count=$((count + 1))
    done < <(find "$F2B_ACTION_D_DIR" -maxdepth 1 -type f -name '*.local' -print0)
  fi

  if [ "$count" -gt 0 ]; then
    if sudo tar -czf "$tarball" -C / -T "$listfile"; then
      echo "✅ 已備份 .local 檔案 -> $tarball"
    else
      tgdb_fail "備份失敗，請檢查權限或磁碟空間" 1 || true
    fi
  else
    tgdb_warn "未找到任何 .local 檔案可備份"
  fi
  rm -f "$listfile"
  ui_pause
}

# 還原 .local 設定（從 $F2B_APP_DIR 選擇備份檔）
restore_fail2ban_local() {
    clear
    echo "=================================="
    echo "❖ 還原 Fail2ban .local ❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }
    if [ ! -d "$F2B_APP_DIR" ]; then
        tgdb_warn "未找到備份目錄：$F2B_APP_DIR"
        ui_pause; return 1
    fi
    local files
    mapfile -t files < <(find "$F2B_APP_DIR" -maxdepth 1 -type f -name 'fail2ban-local*.tar.gz' -printf '%p\n' 2>/dev/null | sort)
    if [ ${#files[@]} -eq 0 ]; then
        tgdb_warn "未找到任何備份檔"
        ui_pause; return 1
    fi

	    echo "可用備份檔："
	    echo "----------------------------------"
	    local i
	    for i in "${!files[@]}"; do
	        echo "$((i + 1)). ${files[$i]}"
	    done
	    echo "----------------------------------"
	    local idx
	    if ! ui_prompt_index idx "請選擇要還原的備份 [1-${#files[@]}]（預設 ${#files[@]}，輸入 0 取消）: " 1 "${#files[@]}" "${#files[@]}" "0"; then
	        echo "操作已取消。"
	        ui_pause
	        return 0
	    fi
	
	    local tarball
	    tarball="${files[$((idx - 1))]}"
	
	    echo "→ 將還原備份檔：$tarball"
	    if ! ui_confirm_yn "確認繼續嗎？(Y/n，預設 Y): " "Y"; then
	        echo "操作已取消。"
	        ui_pause
	        return 0
	    fi
	
	    echo "→ 正在還原：$tarball"
	    sudo tar -xzf "$tarball" -C /
	    if command -v systemctl >/dev/null 2>&1; then
	        sudo systemctl reload fail2ban 2>/dev/null || sudo systemctl restart fail2ban 2>/dev/null || true
	    fi
	    echo "✅ 還原完成"
	    ui_pause
	}

# 顯示 SSH 防護紀錄（過去 Ban 事件）
show_ssh_protection_logs() {
    clear
    echo "=================================="
    echo "❖ 查看 SSH 防護紀錄 ❖"
    echo "=================================="
    sudo fail2ban-client status sshd
	ui_pause
}

# 顯示 Nginx 防護紀錄
show_nginx_protection_logs() {
    clear
    echo "=================================="
    echo "❖ 查看 Nginx 防護紀錄 ❖"
    echo "=================================="
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        tgdb_warn "未找到 fail2ban-client，請確認 Fail2ban 是否已安裝"
        ui_pause
        return 1
    fi

    local jails
    jails=$(sudo fail2ban-client status 2>/dev/null | awk -F":" '/Jail list/{print $2}' | tr -d '[:space:]')
    if [ -z "$jails" ]; then
        tgdb_warn "尚未啟用任何 jail"
        ui_pause
        return 0
    fi

    local found="false" j
    IFS="," read -r -a arr <<< "$jails"
    for j in "${arr[@]}"; do
        case "$j" in
            nginx-*)
                found="true"
                echo
                echo "===== Jail: $j ====="
                sudo fail2ban-client status "$j" 2>/dev/null || true
                ;;
        esac
    done

    if [ "$found" != "true" ]; then
        tgdb_warn "目前未啟用任何 Nginx 相關 jail（nginx-*）"
    fi
	ui_pause
}

# 查看自訂 jail 紀錄（互動輸入 jail 名稱）
show_custom_jail_logs() {
    clear
    echo "=================================="
    echo "❖ 查看自訂 Jail 紀錄 ❖"
    echo "=================================="
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        tgdb_warn "未找到 fail2ban-client，請確認 Fail2ban 是否已安裝"
        ui_pause
        return 1
    fi

    echo "目前可用的 jail："
    echo "----------------------------------"
    local jails
    jails=$(sudo fail2ban-client status 2>/dev/null | awk -F":" '/Jail list/{print $2}' | tr -d '[:space:]')
    if [ -z "$jails" ]; then
        tgdb_warn "尚未啟用任何 jail"
        ui_pause
        return 0
    fi

    IFS="," read -r -a arr <<< "$jails"
    local i idx=0
    for i in "${!arr[@]}"; do
        echo "$((i + 1)). ${arr[$i]}"
    done
    echo "0. 返回"
    echo "----------------------------------"
    ui_prompt_index idx "請選擇要查看的 jail [0-${#arr[@]}]（預設 0）: " 0 "${#arr[@]}" "0" ""
    if [ "$idx" -eq 0 ]; then
        echo "已取消。"
        ui_pause
        return 0
    fi
    local name
    name="${arr[$((idx - 1))]}"

    echo
    echo "===== Jail: $name ====="
    if ! sudo fail2ban-client status "$name" 2>/dev/null; then
        tgdb_err "找不到名為 \"$name\" 的 jail，請確認名稱是否正確。"
    fi
	ui_pause
}

# 實時監控（使用 tail -f 或 docker logs -f）
realtime_protection_view() {
    clear
    echo "=================================="
    echo "❖ 查看實時防護 ❖"
    echo "=================================="
    echo "按 Ctrl+C 結束。"
    if [ -f /var/log/fail2ban.log ]; then
        sudo tail -n 50 -f /var/log/fail2ban.log
    elif command -v journalctl >/dev/null 2>&1; then
        sudo journalctl -u fail2ban -n 50 -f
    else
        tgdb_warn "找不到 /var/log/fail2ban.log，且無法使用 journalctl"
    fi
}

# 設定/切換 sshd 的日誌來源（支援 systemd/journal 與檔案）
configure_sshd_log_backend() {
    clear
    echo "=================================="
    echo "❖ 設定 SSH 日誌來源 ❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }

    local has_file has_journal
    has_file="false"; has_journal="false"
    if [ -f /var/log/auth.log ] || [ -f /var/log/secure ]; then
        has_file="true"
    fi
    if command -v journalctl >/dev/null 2>&1; then
        has_journal="true"
    fi

    echo "可用來源："
    echo "1. systemd/journal 後端$([ "$has_journal" = "true" ] && echo " (可用)" || echo " (不可用)")"
    echo "2. 檔案後端（%(sshd_log)s）$([ "$has_file" = "true" ] && echo " (建議)" || echo " (可能無日誌檔)")"
    echo "----------------------------------"
    read -r -e -p "請選擇 [1-2]: " mode
    case "$mode" in
        1)
            if [ "$has_journal" != "true" ]; then
                tgdb_err "本系統無 journalctl，無法使用 systemd 後端"
                ui_pause; return 1
            fi
            _write_sshd_backend_local_systemd
            ;;
        2)
            _write_sshd_backend_local_file
            ;;
        *)
            tgdb_err "無效選擇"; ui_pause; return 1 ;;
    esac

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl reload fail2ban 2>/dev/null || sudo systemctl restart fail2ban 2>/dev/null || true
    fi
    echo "✅ 已更新 sshd 日誌來源（$F2B_TGDB_SSHD_LOCAL）"
    echo "ℹ️ 建議執行：fail2ban-client --test 以驗證配置"
    ui_pause
}

# 直接編輯 .local（依部署模式選擇對應 jail.local）
edit_local_config() {
    clear
    echo "=================================="
    echo "❖ 編輯 jail.local ❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }
    local conf_root file
    conf_root=$(get_fail2ban_conf_root)
    file="$conf_root/jail.local"
    sudo mkdir -p "$conf_root"
    if [ ! -f "$file" ]; then
        echo "# 由 TGDB 建立的最小配置" | sudo tee "$file" >/dev/null
    fi

    if ensure_editor; then
        sudo -E "$EDITOR" "$file"
    else
        tgdb_warn "找不到可用編輯器（nano/vim/vi），請手動編輯：$file"
        ui_pause
        return 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl reload fail2ban 2>/dev/null || sudo systemctl restart fail2ban 2>/dev/null || true
        echo "✅ 已嘗試重載 Fail2ban"
    fi
    ui_pause
}

# 編輯 jail.d 的 .local（TGDB 產生檔案與使用者自訂檔案都會在這裡）
edit_jail_d_local_config() {
  clear
  echo "=================================="
  echo "❖ 編輯 jail.d 的 .local ❖"
  echo "=================================="
  require_root || { ui_pause; return 1; }

  local dir="$F2B_JAIL_D_DIR"
  sudo mkdir -p "$dir"

  local -a files
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name '*.local' -printf '%f\n' 2>/dev/null | sort)

  local i max
  max=${#files[@]}

  echo "可編輯檔案：$dir"
  echo "----------------------------------"
  if [ "$max" -gt 0 ]; then
    for i in "${!files[@]}"; do
      echo "$((i + 1)). ${files[$i]}"
    done
  else
    echo "（目前沒有任何 *.local 檔案）"
  fi
  echo "$((max + 1)). 新增 .local 檔案"
  echo "0. 返回"
  echo "----------------------------------"

  local choice=0
  ui_prompt_index choice "請選擇要編輯的檔案 [0-$((max + 1))]（預設 0）: " 0 "$((max + 1))" "0" "x"
  if [ "$choice" -eq 0 ]; then
    return 0
  fi

  local file
  if [ "$choice" -eq $((max + 1)) ]; then
    local name
    read -r -e -p "請輸入新檔名（例如：zz-tgdb-nginx-tune.local，Enter 取消）: " name
    if [ -z "$name" ]; then
      echo "已取消。"
      ui_pause
      return 0
    fi
    case "$name" in
      */*) tgdb_err "檔名不可包含路徑分隔符 /"; ui_pause; return 1 ;;
    esac
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      tgdb_err "檔名僅允許英數、點、底線與減號（例如：zz-tgdb-nginx-tune.local）"
      ui_pause
      return 1
    fi
    case "$name" in
      *.local) ;;
      *) name="${name}.local" ;;
    esac
    file="$dir/$name"
    if [ ! -f "$file" ]; then
      echo "# TGDB：自訂 jail 覆寫檔（只放你要調整的參數）" | sudo tee "$file" >/dev/null
      echo "✅ 已建立：$file"
    fi
  else
    file="$dir/${files[$((choice - 1))]}"
  fi

  if ensure_editor; then
    sudo -E "$EDITOR" "$file"
  else
    tgdb_warn "找不到可用編輯器（nano/vim/vi），請手動編輯：$file"
    ui_pause
    return 1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl reload fail2ban 2>/dev/null || sudo systemctl restart fail2ban 2>/dev/null || true
    echo "✅ 已嘗試重載 Fail2ban"
  fi
  ui_pause
}

# 編輯 filter.d 的 .local（從 .conf 複製或建立空白）
edit_filter_local() {
    clear
    echo "=================================="
    echo "❖ 編輯 filter.d 的 .local ❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }
    local dir="/etc/fail2ban/filter.d"
    if [ ! -d "$dir" ]; then tgdb_warn "找不到 $dir"; ui_pause; return 1; fi
    echo "可用的過濾器（.conf/.local）："
    find "$dir" -maxdepth 1 -type f \( -name '*.conf' -o -name '*.local' \) -printf '%f\n' 2>/dev/null | sort | sed 's/^/ - /'
    echo "----------------------------------"
    read -r -e -p "請輸入要編輯的過濾器名稱（不含副檔名，例如：sshd）: " name
    if [ -z "$name" ]; then tgdb_err "名稱不可為空"; ui_pause; return 1; fi
    local src="$dir/$name.conf" dst="$dir/$name.local"
    if [ ! -f "$dst" ]; then
        if [ -f "$src" ]; then
            sudo cp -a "$src" "$dst"
            echo "✅ 已從 $src 建立 $dst"
        else
            echo "# TGDB: 新建 $name.local" | sudo tee "$dst" >/dev/null
            tgdb_warn "未找到 $src，已建立空白 $dst"
        fi
    fi
    if ensure_editor; then
        sudo -E "$EDITOR" "$dst"
    else
        tgdb_warn "找不到可用編輯器（nano/vim/vi），請手動編輯：$dst"
    fi
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl reload fail2ban 2>/dev/null || sudo systemctl restart fail2ban 2>/dev/null || true
    fi
	ui_pause
}

# 編輯 action.d 的 .local（從 .conf 複製或建立空白）
edit_action_local() {
    clear
    echo "=================================="
    echo "❖ 編輯 action.d 的 .local ❖"
    echo "=================================="
    require_root || { ui_pause; return 1; }
    local dir="/etc/fail2ban/action.d"
    if [ ! -d "$dir" ]; then tgdb_warn "找不到 $dir"; ui_pause; return 1; fi
    echo "可用的動作（.conf/.local）："
    find "$dir" -maxdepth 1 -type f \( -name '*.conf' -o -name '*.local' \) -printf '%f\n' 2>/dev/null | sort | sed 's/^/ - /'
    echo "----------------------------------"
    read -r -e -p "請輸入要編輯的動作名稱（不含副檔名，例如：nftables）: " name
    if [ -z "$name" ]; then tgdb_err "名稱不可為空"; ui_pause; return 1; fi
    local src="$dir/$name.conf" dst="$dir/$name.local"
    if [ ! -f "$dst" ]; then
        if [ -f "$src" ]; then
            sudo cp -a "$src" "$dst"
            echo "✅ 已從 $src 建立 $dst"
        else
            echo "# TGDB: 新建 $name.local" | sudo tee "$dst" >/dev/null
            tgdb_warn "未找到 $src，已建立空白 $dst"
        fi
    fi
    if ensure_editor; then
        sudo -E "$EDITOR" "$dst"
    else
        tgdb_warn "找不到可用編輯器（nano/vim/vi），請手動編輯：$dst"
    fi
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl reload fail2ban 2>/dev/null || sudo systemctl restart fail2ban 2>/dev/null || true
    fi
	ui_pause
}

# 白名單：管理 jail.local 的 [DEFAULT] ignoreip
_get_default_ignoreip() {
    local file="$1"
    sudo awk '
        BEGIN { in_default=0 }
        /^[[:space:]]*\\[DEFAULT\\][[:space:]]*$/ { in_default=1; next }
        /^[[:space:]]*\\[[^]]+\\][[:space:]]*$/ { in_default=0 }
        in_default && /^[[:space:]]*ignoreip[[:space:]]*=/ {
            sub(/^[[:space:]]*ignoreip[[:space:]]*=[[:space:]]*/, "", $0)
            gsub(/[[:space:]]+$/, "", $0)
            print
            exit
        }
    ' "$file" 2>/dev/null || true
}

_set_default_ignoreip() {
    local file="$1"
    local value="$2"
    local tmp
    tmp=$(mktemp)
    sudo cat "$file" | awk -v new_value="$value" '
        BEGIN { in_default=0; wrote=0 }
        /^[[:space:]]*\\[DEFAULT\\][[:space:]]*$/ {
            in_default=1
            print
            next
        }
        /^[[:space:]]*\\[[^]]+\\][[:space:]]*$/ {
            if (in_default && !wrote) {
                print "ignoreip = " new_value
                wrote=1
            }
            in_default=0
            print
            next
        }
        {
            if (in_default && $0 ~ /^[[:space:]]*ignoreip[[:space:]]*=/) {
                if (!wrote) {
                    print "ignoreip = " new_value
                    wrote=1
                }
                next
            }
            print
        }
        END {
            if (!wrote) {
                if (!in_default) {
                    print "[DEFAULT]"
                }
                print "ignoreip = " new_value
            }
        }
    ' >"$tmp"
    sudo cp "$tmp" "$file"
    rm -f "$tmp"
}

_normalize_ignoreip_tokens() {
    local input="${1//,/ }"
    local -a tokens=()
    local item
    for item in $input; do
        [ -n "$item" ] && tokens+=("$item")
    done

    local -A seen=()
    local -a out=()

    # 預設永遠保留本機回圈（避免誤封自己）
    for item in 127.0.0.1/8 ::1; do
        if [ -z "${seen[$item]:-}" ]; then
            seen[$item]=1
            out+=("$item")
        fi
    done

    for item in "${tokens[@]}"; do
        if [ -z "${seen[$item]:-}" ]; then
            seen[$item]=1
            out+=("$item")
        fi
    done

    printf '%s' "${out[*]}"
}

whitelist_add() {
  clear
  echo "=================================="
  echo "❖ 添加白名單 IP ❖"
  echo "=================================="
  require_root || { ui_pause; return 1; }

  read -r -e -p "請輸入 IP（IPv4/IPv6 皆可）: " ip
  if [ -z "$ip" ]; then tgdb_err "IP 不可為空"; ui_pause; return 1; fi

  local conf_root file current normalized
  conf_root=$(get_fail2ban_conf_root)
  file="$conf_root/jail.local"
  sudo mkdir -p "$conf_root"
  if [ ! -f "$file" ]; then
    echo "[DEFAULT]" | sudo tee "$file" >/dev/null
  fi

  current=$(_get_default_ignoreip "$file")
  normalized=$(_normalize_ignoreip_tokens "$current $ip")

  case " $current " in
    *" $ip "*) tgdb_warn "$ip 已在 ignoreip 中" ;;
    *)
      _set_default_ignoreip "$file" "$normalized"
      echo "✅ 已添加 $ip 至 ignoreip"
      ;;
  esac

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl reload fail2ban 2>/dev/null || true
  fi
  ui_pause
}

whitelist_remove() {
  clear
  echo "=================================="
  echo "❖ 移除白名單 IP ❖"
  echo "=================================="
  require_root || { ui_pause; return 1; }

  read -r -e -p "請輸入要移除的 IP: " ip
  if [ -z "$ip" ]; then tgdb_err "IP 不可為空"; ui_pause; return 1; fi

  local conf_root file current
  conf_root=$(get_fail2ban_conf_root)
  file="$conf_root/jail.local"
  if [ ! -f "$file" ]; then
    tgdb_warn "未找到 $file"
    ui_pause
    return 1
  fi

  current=$(_get_default_ignoreip "$file")
  if [ -z "$current" ]; then
    tgdb_warn "未在 $file 的 [DEFAULT] 找到 ignoreip 條目"
    ui_pause
    return 0
  fi

  case " $current " in
    *" $ip "*) ;;
    *)
      tgdb_warn "ignoreip 中未包含：$ip"
      ui_pause
      return 0
      ;;
  esac

  local filtered token normalized
  filtered=""
  for token in ${current//,/ }; do
    [ "$token" = "$ip" ] && continue
    filtered="$filtered $token"
  done
  normalized=$(_normalize_ignoreip_tokens "$filtered")
  _set_default_ignoreip "$file" "$normalized"

  echo "✅ 已從 ignoreip 移除 $ip（127.0.0.1/8 與 ::1 會保留）"
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl reload fail2ban 2>/dev/null || true
  fi
  ui_pause
}

# 清空當前所有 jail 的黑名單（已封鎖 IP）
clear_all_bans() {
  clear
  echo "=================================="
  echo "❖ 清除當前黑名單 IP ❖"
  echo "=================================="
  require_root || { ui_pause; return 1; }

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    tgdb_warn "未找到 fail2ban-client，請確認 Fail2ban 是否已安裝"
    ui_pause
    return 1
  fi

  echo "→ 嘗試使用 fail2ban-client unban --all 清空全部 jail 的封鎖..."
  if sudo fail2ban-client unban --all >/dev/null 2>&1; then
    echo "✅ 已送出 unban --all"
    ui_pause
    return 0
  fi

  tgdb_warn "unban --all 失敗，改用逐一 jail 清除（較慢）..."
  local jails
  jails=$(sudo fail2ban-client status 2>/dev/null | awk -F":" '/Jail list/{print $2}' | tr -d '[:space:]')
  if [ -z "$jails" ]; then
    tgdb_warn "未發現任何 jail"
    ui_pause
    return 0
  fi

  local j banned ip
  IFS="," read -r -a arr <<< "$jails"
  for j in "${arr[@]}"; do
    echo "→ 清除 jail: $j"
    banned=$(sudo fail2ban-client status "$j" 2>/dev/null | awk -F":" '/Banned IP list/{print $2}')
    if [ -n "$banned" ]; then
      for ip in $banned; do
        sudo fail2ban-client set "$j" unbanip "$ip" >/dev/null 2>&1 || true
      done
    fi
  done
  echo "✅ 已嘗試清空所有 jail 的封鎖 IP"
  ui_pause
}

# Nginx 防護開關（使用 /etc/fail2ban/jail.d/tgdb-nginx.local 管理）
_nginx_toggle_file="$F2B_JAIL_D_DIR/tgdb-nginx.local"

_nginx_status() {
    if [ ! -f "$_nginx_toggle_file" ]; then
        echo disabled
        return 0
    fi

    if [ "$(id -u)" -eq 0 ]; then
        if grep -Eq '^\s*enabled\s*=\s*true' "$_nginx_toggle_file" 2>/dev/null; then
            echo enabled
        else
            echo disabled
        fi
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo grep -Eq '^\s*enabled\s*=\s*true' "$_nginx_toggle_file" 2>/dev/null; then
            echo enabled
        else
            echo disabled
        fi
        return 0
    fi

    echo disabled
}

# 取得 Nginx 日誌根路徑（容器映射到 TGDB_DIR）
_nginx_log_root() {
    echo "${TGDB_DIR}/nginx/logs"
}

# 過濾器是否存在（避免啟用無對應 filter 的 jail）
_nginx_filter_exists() {
    local jail_name="$1"
    [ -f "$F2B_FILTER_D_DIR/${jail_name}.conf" ]
}

_nginx_filter_uses_error_log() {
    local name="$1"
    local file="$F2B_FILTER_D_DIR/${name}.conf"
    [ -f "$file" ] || return 1
    grep -Eq '^[[:space:]]*before[[:space:]]*=[[:space:]]*nginx-error-common\.conf([[:space:]]*|$)' "$file"
}

_nginx_list_available_filters() {
    find "$F2B_FILTER_D_DIR" -maxdepth 1 -type f -name 'nginx-*.conf' -printf '%f\n' 2>/dev/null \
        | sed 's/\.conf$//' \
        | grep -Ev '^nginx-error-common$' \
        | sort
}

# 依選擇狀態重寫 tgdb-nginx.local
_write_nginx_jails() {
    local nginx_log_root log_access log_error
    nginx_log_root=$(_nginx_log_root)
    log_access="$nginx_log_root/*access*.log"
    log_error="$nginx_log_root/*error*.log"

    local tmp
    tmp=$(mktemp)

    local filter logpath
    while IFS= read -r filter; do
        [ -n "$filter" ] || continue
        logpath="$log_access"
        if _nginx_filter_uses_error_log "$filter"; then
            logpath="$log_error"
        fi
        cat >>"$tmp" <<EOF
[$filter]
enabled = true
port = http,https
logpath = $logpath
EOF
    done < <(_nginx_list_available_filters)

    sudo mkdir -p "$F2B_JAIL_D_DIR"

    if [ -s "$tmp" ]; then
        sudo cp "$tmp" "$_nginx_toggle_file"
        echo "✅ 已更新 Nginx jail 設定：$_nginx_toggle_file"
    else
        sudo rm -f "$_nginx_toggle_file"
        echo "✅ 已關閉所有 Nginx jail（已移除檔案）"
    fi
    rm -f "$tmp"
}

toggle_nginx_protection() {
    clear
    echo "=================================="
    echo "❖ Nginx 防護開關 ❖"
    echo "=================================="
require_root || { ui_pause; return 1; }

    local st
    st=$(_nginx_status)
    echo "日誌路徑：$(_nginx_log_root)"
    echo "目前狀態：$st"
    echo "----------------------------------"
    if [ "$st" = "enabled" ]; then
        if ui_confirm_yn "是否關閉全部 Nginx 防護？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            sudo rm -f "$_nginx_toggle_file"
            if command -v systemctl >/dev/null 2>&1; then
                sudo systemctl reload fail2ban 2>/dev/null || true
            fi
            echo "✅ 已關閉所有 Nginx jail"
        else
            echo "已取消。"
        fi
    else
        if ui_confirm_yn "是否開啟 Nginx 防護（一次啟用所有可用 nginx-* jails）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            _write_nginx_jails
            if command -v systemctl >/dev/null 2>&1; then
                sudo systemctl reload fail2ban 2>/dev/null || true
            fi
            echo "✅ 已開啟 Nginx jails（依系統可用 nginx-* filter 寫入）"
        else
            echo "已取消。"
        fi
    fi
    ui_pause
}

# 子選單：安裝/移除
install_remove_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "Fail2ban 管理需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 安裝/更新/移除 Fail2ban ❖"
        echo "=================================="
        echo "1. 安裝（預設開啟 SSH）"
        echo "2. 更新"
        echo "3. 移除"
        echo "4. 重新載入服務"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-4]: " c
        case "$c" in
            1) install_fail2ban_package ;;
            2) update_fail2ban_package ;;
            3) remove_fail2ban_package ;;
            4) if command -v systemctl >/dev/null 2>&1; then sudo systemctl reload fail2ban 2>/dev/null || sudo systemctl restart fail2ban; ui_pause; fi ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

# 主選單
fail2ban_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "Fail2ban 管理需要互動式終端（TTY）。" 2 || true
        return 2
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ Fail2ban 防護管理 ❖"
        echo "=================================="
        local status  active
        status=$(detect_fail2ban)
        active=${status##*,}
        echo "服務: $([ "$active" = "true" ] && echo 運行中 || echo 未運行)"
        echo "----------------------------------"
        echo "1. 安裝/更新/移除"
        echo "2. 查看 SSH 防護紀錄"
        echo "3. 查看 Nginx 防護紀錄"
        echo "4. 查看自訂 jail 紀錄"
        echo "5. 查看實時防護"
        echo "6. 編輯 jail.local"
        echo "7. 編輯 jail.d 的 .local"
        echo "8. 編輯 filter.d 的 .local"
        echo "9. 編輯 action.d 的 .local"
        echo "10. Nginx 防護開關"
        echo "11. 添加白名單 IP"
        echo "12. 移除白名單 IP"
        echo "13. 備份 .local 至 $F2B_APP_DIR"
        echo "14. 從備份還原 .local"
        echo "15. 清除當前黑名單 IP"
        echo "16. 設定 SSH 日誌來源（journal/檔案）"
        echo "----------------------------------"
        echo "0. 返回主選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-16]: " choice
        case "$choice" in
            1) install_remove_menu ;;
            2) show_ssh_protection_logs ;;
            3) show_nginx_protection_logs ;;
            4) show_custom_jail_logs ;;
            5) realtime_protection_view ;;
            6) edit_local_config ;;
            7) edit_jail_d_local_config ;;
            8) edit_filter_local ;;
            9) edit_action_local ;;
            10) toggle_nginx_protection ;;
            11) whitelist_add ;;
            12) whitelist_remove ;;
            13) backup_fail2ban_local ;;
            14) restore_fail2ban_local ;;
            15) clear_all_bans ;;
            16) configure_sshd_log_backend ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}
