#!/bin/bash

# 系統資訊與系統維護（供 tgdb.sh 呼叫）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

ENV_SETUP_CUSTOM_ITEMS=(
  "1|執行系統維護|2"
  "2|安裝所有基礎工具|4 1"
  "3|初始化 nftables 並開放 80/443/UDP443|3 10"
  "4|更改 SSH 連接埠為預設 25252|3 12"
  "5|設定 DNS 為 1.1.1.1 / 8.8.8.8|3 7"
  "6|設定 Swap 為預設 1G|3 3"
  "7|啟用 BBR+FQ|3 9"
  "8|設定時區為 Asia/Taipei|3 5"
  "9|安裝 Fail2ban（最小 sshd 防護）|3 11"
  "10|安裝 Podman|5 1"
  "11|安裝/更新 rclone|7 1 1"
)

# 顯示系統與服務狀態摘要
show_system_info() {
  [ -t 1 ] && clear

  local hostname os_info kernel_version cpu_arch
  hostname=$(hostname 2>/dev/null || uname -n)
  os_info=$(
    awk -F= '$1=="PRETTY_NAME"{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null || true
  )
  kernel_version=$(uname -r)
  cpu_arch=$(uname -m)

  local cpu_info cpu_cores
  if command -v lscpu >/dev/null 2>&1; then
    cpu_info=$(LC_ALL=C lscpu 2>/dev/null | awk -F': +' '/Model name:/ {print $2; exit}' || true)
  fi
  if [ -z "${cpu_info:-}" ]; then
    cpu_info=$(
      awk -F': *' '
        tolower($1)=="model name" {print $2; exit}
        tolower($1)=="hardware" {print $2; exit}
        tolower($1)=="processor" {print $2; exit}
      ' /proc/cpuinfo 2>/dev/null || true
    )
  fi

  cpu_cores=$(nproc 2>/dev/null || echo "")

  local cpu_usage_percent="未知"
  if [ -r /proc/stat ]; then
    cpu_usage_percent=$(
      awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else printf "%.0f\n", (u-u1)*100/(t-t1)}' \
        <(grep '^cpu ' /proc/stat 2>/dev/null || true) <(sleep 1; grep '^cpu ' /proc/stat 2>/dev/null || true) 2>/dev/null || echo "未知"
    )
  fi

  local load
  load=$(uptime 2>/dev/null | awk '{print $(NF-2), $(NF-1), $NF}' || true)
  if [ -z "${load:-}" ] && [ -r /proc/loadavg ]; then
    load=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || true)
  fi

  local tcp_count="0" udp_count="0"
  if command -v ss >/dev/null 2>&1; then
    tcp_count=$(ss -t 2>/dev/null | awk 'NR>1' | wc -l | awk '{print $1}' || true)
    udp_count=$(ss -u 2>/dev/null | awk 'NR>1' | wc -l | awk '{print $1}' || true)
  fi

  local mem_info swap_info
  if command -v free >/dev/null 2>&1; then
    mem_info=$(free -b 2>/dev/null | awk 'NR==2{printf "%.2f/%.2fM (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}' || true)
    swap_info=$(free -m 2>/dev/null | awk 'NR==3{used=$3; total=$2; if (total == 0) {percentage=0} else {percentage=used*100/total}; printf "%dM/%dM (%d%%)", used, total, percentage}' || true)
  fi

  local disk_info
  disk_info=$(df -h 2>/dev/null | awk '$NF=="/"{printf "%s/%s (%s)", $3, $2, $5}' || true)

  local rx_bytes=0 tx_bytes=0 rx_human="0B" tx_human="0B"
  if [ -r /proc/net/dev ]; then
    read -r rx_bytes tx_bytes < <(awk '
NR>2 {
  gsub(":", "", $1)
  iface=$1
  if (iface=="lo") next
  rx+=$2
  tx+=$10
}
END {printf "%d %d", rx, tx}
    ' /proc/net/dev 2>/dev/null || echo "0 0") || true
    [ -z "${rx_bytes:-}" ] && rx_bytes=0
    [ -z "${tx_bytes:-}" ] && tx_bytes=0
    if [ -n "${rx_bytes:-}" ] && [ "$rx_bytes" -ge 0 ] 2>/dev/null; then
      if [ "$rx_bytes" -ge 1073741824 ] 2>/dev/null; then
        rx_human=$(awk "BEGIN {printf \"%.2fG\", $rx_bytes/1073741824}")
      elif [ "$rx_bytes" -ge 1048576 ] 2>/dev/null; then
        rx_human=$(awk "BEGIN {printf \"%.2fM\", $rx_bytes/1048576}")
      elif [ "$rx_bytes" -ge 1024 ] 2>/dev/null; then
        rx_human=$(awk "BEGIN {printf \"%.2fK\", $rx_bytes/1024}")
      else
        rx_human="${rx_bytes}B"
      fi
    fi
    if [ -n "${tx_bytes:-}" ] && [ "$tx_bytes" -ge 0 ] 2>/dev/null; then
      if [ "$tx_bytes" -ge 1073741824 ] 2>/dev/null; then
        tx_human=$(awk "BEGIN {printf \"%.2fG\", $tx_bytes/1073741824}")
      elif [ "$tx_bytes" -ge 1048576 ] 2>/dev/null; then
        tx_human=$(awk "BEGIN {printf \"%.2fM\", $tx_bytes/1048576}")
      elif [ "$tx_bytes" -ge 1024 ] 2>/dev/null; then
        tx_human=$(awk "BEGIN {printf \"%.2fK\", $tx_bytes/1024}")
      else
        tx_human="${tx_bytes}B"
      fi
    fi
  fi

  local congestion_algorithm="未知" queue_algorithm="未知"
  congestion_algorithm=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "")
  queue_algorithm=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo "")
  [ -z "${congestion_algorithm:-}" ] && congestion_algorithm="未知"
  [ -z "${queue_algorithm:-}" ] && queue_algorithm="未知"

  local dns_addresses
  dns_addresses=$(awk '/^nameserver/{printf "%s ", $2} END {print ""}' /etc/resolv.conf 2>/dev/null || true)

  local isp_info="" country="" city=""
  if command -v curl >/dev/null 2>&1; then
    local ipinfo
    ipinfo=$(curl -fsSL --connect-timeout 3 --max-time 3 ipinfo.io 2>/dev/null || echo "")
    if [ -n "$ipinfo" ]; then
      country=$(echo "$ipinfo" | awk -F'"' '/"country"/{print $4; exit}')
      city=$(echo "$ipinfo" | awk -F'"' '/"city"/{print $4; exit}')
      isp_info=$(echo "$ipinfo" | awk -F'"' '/"org"/{print $4; exit}')
    fi
  fi

  local ipv4_address="未知"
  if declare -F get_ipv4_address >/dev/null 2>&1; then
    ipv4_address="$(get_ipv4_address)"
  else
    if command -v ip >/dev/null 2>&1; then
      ipv4_address=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d'/' -f1 | head -n 1 || true)
    fi
    if [ -z "$ipv4_address" ]; then
      ipv4_address=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi
    [ -z "${ipv4_address:-}" ] && ipv4_address="未知"
  fi

  local timezone="未知"
  if command -v timedatectl >/dev/null 2>&1; then
    timezone=$(timedatectl 2>/dev/null | awk -F': ' '/Time zone/{print $2}' | awk '{print $1}' || true)
  fi
  if [ -z "${timezone:-}" ]; then
    timezone=$(readlink -f /etc/localtime 2>/dev/null | awk -F'/zoneinfo/' 'NF==2{print $2}' || true)
  fi
  [ -z "${timezone:-}" ] && timezone=$(date +%Z 2>/dev/null || echo "未知")

  local current_time_raw current_time
  current_time_raw=$(date "+%Y-%m-%d %I:%M %p" 2>/dev/null || true)
  if [ -z "${current_time_raw:-}" ]; then
    current_time_raw=$(date "+%Y-%m-%d %H:%M" 2>/dev/null || echo "")
  fi
  case "$current_time_raw" in
    *" AM") current_time=${current_time_raw/ AM/ 上午} ;;
    *" PM") current_time=${current_time_raw/ PM/ 下午} ;;
    *) current_time="$current_time_raw" ;;
  esac

  local runtime="未知"
  if [ -r /proc/uptime ]; then
    runtime=$(
      awk -F. '{
        total=$1;
        d=int(total/86400);
        h=int((total%86400)/3600);
        m=int((total%3600)/60);
        out="";
        if (d>0) out=out d "天 ";
        if (h>0) out=out h "時 ";
        out=out m "分";
        print out
      }' /proc/uptime 2>/dev/null || true
    )
  fi

  echo ""
  echo "系統資訊總覽"
  echo "-------------"
  echo "主機名稱:       $hostname"
  echo "系統版本:       $os_info"
  echo "Linux版本:      $kernel_version"
  echo "-------------"
  echo "CPU架構:        $cpu_arch"
  echo "CPU型號:        ${cpu_info:-未知}"
  echo "CPU核心數:      ${cpu_cores:-未知}"
  echo "-------------"
  echo "CPU佔用:        ${cpu_usage_percent}%"
  echo "系統負載:       $load"
  echo "TCP|UDP連線數:  ${tcp_count}|${udp_count}"
  echo "實體記憶體:     ${mem_info:-未知}"
  echo "虛擬記憶體:     ${swap_info:-未知}"
  echo "硬碟佔用:       ${disk_info:-未知}"
  echo "-------------"
  echo "總接收:         $rx_human"
  echo "總發送:         $tx_human"
  echo "-------------"
  echo "網路演算法:     $congestion_algorithm $queue_algorithm"
  echo "-------------"
  echo "運營商:         ${isp_info:-未知}"
  echo "IPv4位址:       $ipv4_address"
  echo "DNS位址:        ${dns_addresses:-未知}"
  echo "地理位置:       ${country:-未知} ${city:-}"
  echo "系統時間:       $timezone $current_time"
  echo "-------------"
  echo "運行時間:       $runtime"
  ui_pause "按任意鍵返回主選單..." "main"
}

# 執行跨發行版系統維護作業
system_maintenance() {
    [ -t 1 ] && clear
    echo "=================================="
    echo "❖ 執行系統維護 ❖"
    echo "=================================="
    
    if ! pkg_has_supported_manager; then
        tgdb_fail "未偵測到受支援的套件管理器（apt/dnf/yum/zypper/pacman/apk）。" 1 || true
        ui_pause "按任意鍵返回主選單..." "main"
        return 1
    fi

    local desc_update desc_upgrade desc_autorem desc_clean
    desc_update="$(pkg_action_description update)"
    desc_upgrade="$(pkg_action_description upgrade)"
    desc_autorem="$(pkg_action_description autoremove)"
    desc_clean="$(pkg_action_description clean)"

    echo "步驟 1/4: 更新套件列表/索引 (${desc_update})"
    pkg_update

    echo ""
    echo "步驟 2/4: 升級所有套件 (${desc_upgrade})"
    pkg_upgrade_all

    echo ""
    echo "步驟 3/4: 清理不需要的套件 (${desc_autorem})"
    pkg_autoremove

    echo ""
    echo "步驟 4/4: 清理套件快取 (${desc_clean})"
    pkg_clean

    echo ""
    echo "✅ 系統維護完成"
    ui_pause "按任意鍵返回主選單..." "main"
}

ensure_default_shortcut_t() {
  local script_path target target_resolved
  local marker_file=""
  local existing_shortcut=0 link link_resolved

  script_path="${SCRIPT_PATH:-}"
  if [ -z "$script_path" ]; then
    script_path="$(readlink -f "${BASH_SOURCE[1]:-$0}" 2>/dev/null || echo "${BASH_SOURCE[1]:-$0}")"
  fi
  script_path="$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")"
  [ -n "$script_path" ] || return 0

  if [ -n "${TGDB_DIR:-}" ]; then
    marker_file="$TGDB_DIR/.default_shortcut_t_initialized"
    if [ -f "$marker_file" ]; then
      return 0
    fi
  fi

  target="/usr/local/bin/t"
  [ -d "/usr/local/bin" ] || return 0

  for link in /usr/local/bin/*; do
    [ -e "$link" ] || continue
    [ -L "$link" ] || continue
    link_resolved="$(readlink -f "$link" 2>/dev/null || true)"
    if [ "$link_resolved" = "$script_path" ]; then
      existing_shortcut=1
      break
    fi
  done

  if [ "$existing_shortcut" -eq 1 ]; then
    if [ -n "${marker_file:-}" ]; then
      mkdir -p "$(dirname "$marker_file")" 2>/dev/null || true
      printf '%s\n' "existing-shortcut" >"$marker_file" 2>/dev/null || true
    fi
    return 0
  fi

  if [ -L "$target" ]; then
    target_resolved="$(readlink -f "$target" 2>/dev/null || true)"
    if [ "$target_resolved" = "$script_path" ]; then
      if [ -n "${marker_file:-}" ]; then
        mkdir -p "$(dirname "$marker_file")" 2>/dev/null || true
        printf '%s\n' "already-linked" >"$marker_file" 2>/dev/null || true
      fi
      return 0
    fi
    if [ -n "${marker_file:-}" ]; then
      mkdir -p "$(dirname "$marker_file")" 2>/dev/null || true
      printf '%s\n' "target-occupied" >"$marker_file" 2>/dev/null || true
    fi
    return 0
  fi

  if [ -e "$target" ]; then
    if [ -n "${marker_file:-}" ]; then
      mkdir -p "$(dirname "$marker_file")" 2>/dev/null || true
      printf '%s\n' "target-file-exists" >"$marker_file" 2>/dev/null || true
    fi
    return 0
  fi

  if ! require_root; then
    return 0
  fi

  chmod +x "$script_path" 2>/dev/null || true
  if _tgdb_run_privileged ln -s "$script_path" "$target"; then
    echo "✅ 已自動建立預設快捷鍵：t"
    if [ -n "${marker_file:-}" ]; then
      mkdir -p "$(dirname "$marker_file")" 2>/dev/null || true
      printf '%s\n' "created" >"$marker_file" 2>/dev/null || true
    fi
  fi
  return 0
}

# 快捷鍵管理：列出、設定與更換執行快捷鍵
manage_shortcuts() {
  while true; do
    clear
    echo "=================================="
    echo "❖ 快捷鍵管理 ❖"
    echo "=================================="

    # SCRIPT_PATH 由 tgdb.sh 設定；若此模組在其他入口被 source，則改用呼叫端路徑推導。
    local script_path="${SCRIPT_PATH:-}"
    if [ -z "$script_path" ]; then
      script_path="$(readlink -f "${BASH_SOURCE[1]:-$0}" 2>/dev/null || echo "${BASH_SOURCE[1]:-$0}")"
    fi
    script_path="$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")"
    echo "腳本位置: $script_path"
    echo ""

    echo "當前快捷鍵："
    local found_shortcuts=()
    if [ -d "/usr/local/bin" ]; then
      for link in /usr/local/bin/*; do
        if [ -L "$link" ] && [ "$(readlink -f "$link" 2>/dev/null || true)" = "$script_path" ]; then
          found_shortcuts+=("$(basename "$link")")
        fi
      done
    fi

    if [ ${#found_shortcuts[@]} -eq 0 ]; then
      tgdb_warn "沒有設定快捷鍵"
    elif [ ${#found_shortcuts[@]} -eq 1 ]; then
      echo "✅ ${found_shortcuts[0]}"
    else
      tgdb_warn "偵測到多個快捷鍵（異常狀態，建議先移除再重新設定）："
      local shortcut
      for shortcut in "${found_shortcuts[@]}"; do
        echo "✅ $shortcut"
      done
    fi

    echo ""
    echo "可用操作："
    echo "1. 設定/更換快捷鍵"
    echo "2. 移除快捷鍵"
    echo "----------------------------------"
    echo "0. 返回主選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-2]: " shortcut_choice

    case "$shortcut_choice" in
      1)
        echo ""
        read -r -e -p "請輸入新的快捷鍵名稱: " new_shortcut

        if [ -z "$new_shortcut" ]; then
          tgdb_err "快捷鍵名稱不能為空"
          ui_pause "按任意鍵返回..." "main"
          continue
        fi

        if [[ ! "$new_shortcut" =~ ^[a-zA-Z0-9_-]+$ ]]; then
          tgdb_err "快捷鍵名稱只能包含字母、數字、底線和連字號"
          ui_pause "按任意鍵返回..." "main"
          continue
        fi

        if ! require_root; then
          ui_pause "按任意鍵返回..." "main"
          continue
        fi

        echo "正在設定快捷鍵 '$new_shortcut'..."

        chmod +x "$script_path" 2>/dev/null || true

        if [ ${#found_shortcuts[@]} -gt 0 ]; then
          local old_shortcut
          for old_shortcut in "${found_shortcuts[@]}"; do
            if _tgdb_run_privileged rm -f "/usr/local/bin/$old_shortcut"; then
              echo "移除舊快捷鍵: $old_shortcut"
            else
              tgdb_err "移除舊快捷鍵失敗: $old_shortcut"
            fi
          done
        fi

        if [ -L "/usr/local/bin/$new_shortcut" ] || [ -f "/usr/local/bin/$new_shortcut" ]; then
          if _tgdb_run_privileged rm -f "/usr/local/bin/$new_shortcut"; then
            echo "移除現有的 '$new_shortcut'"
          else
            tgdb_err "移除現有的 '$new_shortcut' 失敗"
          fi
        fi

        if _tgdb_run_privileged ln -s "$script_path" "/usr/local/bin/$new_shortcut"; then
          echo "✅ 快捷鍵 '$new_shortcut' 設定成功！"
          echo "   現在您可以使用 '$new_shortcut' 來執行此腳本"
        else
          tgdb_err "設定快捷鍵失敗，請檢查權限"
        fi
        ui_pause "按任意鍵返回..." "main"
        ;;
      2)
        if [ ${#found_shortcuts[@]} -eq 0 ]; then
          echo ""
          tgdb_warn "沒有可移除的快捷鍵"
          ui_pause "按任意鍵返回..." "main"
          continue
        fi

        if ! require_root; then
          ui_pause "按任意鍵返回..." "main"
          continue
        fi

        local -a remove_targets=("${found_shortcuts[@]}")

        echo ""
        echo "將移除以下快捷鍵："
        local target
        for target in "${remove_targets[@]}"; do
          echo " - $target"
        done

        local removed_any=0
        for target in "${remove_targets[@]}"; do
          if _tgdb_run_privileged rm -f "/usr/local/bin/$target"; then
            echo "✅ 已移除: $target"
            removed_any=1
          else
            tgdb_err "移除失敗: $target"
          fi
        done

        if [ "$removed_any" -eq 1 ]; then
          echo "✅ 快捷鍵已移除"
        fi
        ui_pause "按任意鍵返回..." "main"
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

# 環境設定精靈 - 預設流程
env_setup_default_flow() {
  clear
  echo "=================================="
  echo "❖ 環境設定（預設）❖"
  echo "=================================="
  echo "本流程將依序執行："
  echo "  1. 系統維護          "
  echo "  2. 安裝所有基礎工具    "
  echo "  3. 初始化 nftables（並開放 TCP 80/443、UDP 443）"
  echo "  4. 更改 SSH 連接埠為預設 25252"
  echo "  5. 安裝 Fail2ban（最小 sshd 防護）"
  echo "  6. 設定 DNS：1.1.1.1、8.8.8.8"
  echo "  7. 設定 Swap：1G"
  echo "  8. 啟用 BBR+FQ"
  echo "  9. 設定時區：Asia/Taipei"
  echo "  10. 安裝 Podman         "
  echo "  11. 安裝/更新 rclone    "
  echo "----------------------------------"
  echo "※ 未來可在中間插入額外步驟，"
  echo "  實際執行仍會依照固定順序進行。"
  echo "----------------------------------"
  if ! ui_confirm_yn "確認開始執行嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    echo "已取消預設環境設定。"
	    ui_pause "按任意鍵返回主選單..." "main"
	    return 0
	  fi

  local steps=(
    "系統維護|2"
    "安裝所有基礎工具|4 1"
    "初始化 nftables 並開放 80/443/UDP443|3 10"
    "更改 SSH 連接埠為預設 25252|3 12"
    "安裝 Fail2ban（最小 sshd 防護）|3 11"
    "設定 DNS：1.1.1.1 / 8.8.8.8|3 7"
    "設定 Swap：1G|3 3"
    "啟用 BBR+FQ|3 9"
    "設定時區：Asia/Taipei|3 5"
    "安裝 Podman|5 1"
    "安裝/更新 rclone|7 1 1"
  )

  local item desc cmd status
  for item in "${steps[@]}"; do
    desc=${item%%|*}
    cmd=${item#*|}

    echo "➡️ 開始：$desc"
    local -a args=()
    IFS=' ' read -r -a args <<< "$cmd" || true
    if env_setup_run_cli "${args[@]}"; then
      echo "✅ 完成：$desc"
	    else
	      status=$?
	      tgdb_warn "步驟失敗 (退出碼 $status)：$desc"
	      if ! ui_confirm_yn "是否繼續之後的步驟？(Y/n，預設 Y): " "Y"; then
	        echo "已中止後續步驟。"
		        ui_pause "按任意鍵返回主選單..." "main"
		        return 1
		      fi
		    fi
    echo "----------------------------------"
  done

  echo "✅ 預設環境設定流程已完成。"
	  ui_pause "按任意鍵返回主選單..." "main"
}

# 環境設定精靈 - 自選流程
env_setup_custom_flow() {
  while true; do
    clear
    echo "=================================="
    echo "❖ 環境設定（自選）❖"
    echo "=================================="
    echo "可選擇以下步驟，將依照『編號由小到大』順序執行："
    echo ""

    local item code desc cli
    for item in "${ENV_SETUP_CUSTOM_ITEMS[@]}"; do
      IFS='|' read -r code desc cli <<< "$item"
      printf "  %s) %s\n" "$code" "$desc"
    done

    echo "----------------------------------"
    echo "提示："
    echo "  - 可一次輸入多個編號，以空白分隔，例如：1 3 7"
    echo "  - 實際執行時會依照編號大小排序，不受輸入順序影響"
    echo "----------------------------------"
    read -r -e -p "請輸入要執行的編號（輸入 0 取消）: " selection

    selection="${selection#"${selection%%[![:space:]]*}"}"
    selection="${selection%"${selection##*[![:space:]]}"}"

    if [ -z "$selection" ] || [ "$selection" = "0" ]; then
      echo "已取消自選環境設定。"
	      ui_pause "按任意鍵返回主選單..." "main"
	      return 0
	    fi

    local -a tokens=()
    IFS=' ' read -r -a tokens <<< "$selection" || true
    if [ "${#tokens[@]}" -eq 0 ]; then
      echo "尚未選擇任何有效編號，請重新輸入。"
      sleep 1
      continue
    fi

    declare -A selected_codes=()
    local token
	    local has_valid=0
	    for token in "${tokens[@]}"; do
	      if [[ ! "$token" =~ ^[0-9]+$ ]]; then
	        tgdb_warn "忽略無效輸入：$token"
	        continue
	      fi
	      [ "$token" = "0" ] && continue
	      selected_codes["$token"]=1
	      has_valid=1
	    done

    if [ "$has_valid" -ne 1 ]; then
      echo "尚未選擇任何有效編號，請重新輸入。"
      sleep 1
      continue
    fi

    echo ""
    echo "將依照以下順序執行："
    local any_matched=0
    for item in "${ENV_SETUP_CUSTOM_ITEMS[@]}"; do
      IFS='|' read -r code desc cli <<< "$item"
      if [ "${selected_codes[$code]+x}" = "x" ]; then
        printf "  %s) %s\n" "$code" "$desc"
        any_matched=1
      fi
    done

	    if [ "$any_matched" -ne 1 ]; then
	      tgdb_warn "輸入的編號未對應到任何已定義步驟，請重新輸入。"
	      sleep 1
	      continue
	    fi

    echo "----------------------------------"
    if ! ui_confirm_yn "確認開始執行嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      echo "已取消自選環境設定。"
	      ui_pause "按任意鍵返回主選單..." "main"
	      return 0
	    fi

    local status
    for item in "${ENV_SETUP_CUSTOM_ITEMS[@]}"; do
      IFS='|' read -r code desc cli <<< "$item"
      if [ "${selected_codes[$code]+x}" != "x" ]; then
        continue
      fi
      echo "➡️ 開始：$desc"
      local -a args=()
      IFS=' ' read -r -a args <<< "$cli" || true
      if env_setup_run_cli "${args[@]}"; then
        echo "✅ 完成：$desc"
	      else
	        status=$?
	        tgdb_warn "步驟失敗 (退出碼 $status)：$desc"
	        if ! ui_confirm_yn "是否繼續之後的步驟？(Y/n，預設 Y): " "Y"; then
	          echo "已中止後續步驟。"
		          ui_pause "按任意鍵返回主選單..." "main"
		          return 1
	        fi
	      fi
      echo "----------------------------------"
    done

    echo "✅ 自選環境設定流程已完成。"
	    ui_pause "按任意鍵返回主選單..." "main"
	    return 0
	  done
}

# 環境設定精靈主選單
env_setup_menu() {
  while true; do
    clear
    echo "=================================="
    echo "❖ 快速環境設定 ❖"
    echo "=================================="
    echo "1. 使用預設設定（推薦）"
    echo "2. 自選設定（常用步驟組合）"
    echo "----------------------------------"
    echo "0. 返回主選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-2]: " choice

    case "$choice" in
      1)
        env_setup_default_flow
        ;;
      2)
        env_setup_custom_flow
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
