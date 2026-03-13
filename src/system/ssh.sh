#!/bin/bash

# 系統管理：SSH 與登入安全（現代 VPS 硬化）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

TGDB_SSH_DEFAULT_PORT="25252"

SSH_SSHD_CONFIG="/etc/ssh/sshd_config"
SSH_TGDB_SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSH_TGDB_SSHD_DROPIN_FILE="${SSH_TGDB_SSHD_DROPIN_DIR}/99-tgdb.conf"

ssh__sshd_bin() {
  if command -v sshd >/dev/null 2>&1; then
    command -v sshd
    return 0
  fi

  if [ -x /usr/sbin/sshd ]; then
    echo "/usr/sbin/sshd"
    return 0
  fi

  if [ -x /sbin/sshd ]; then
    echo "/sbin/sshd"
    return 0
  fi

  return 1
}

# 檢查指定埠是否被佔用（優先使用 ss，其次 netstat/lsof）
ssh_is_port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    sudo ss -tuln 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"
    return $?
  elif command -v netstat >/dev/null 2>&1; then
    sudo netstat -tuln 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"
    return $?
  elif command -v lsof >/dev/null 2>&1; then
    sudo lsof -i -P -n 2>/dev/null | grep -qE "(:|\\.)${port}([[:space:]]|$)"
    return $?
  fi
  return 1
}

ssh__timestamp() {
  date +%Y%m%d-%H%M%S
}

ssh__backup_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return 1
  fi

  local backup
  backup="${file}.tgdb.bak.$(ssh__timestamp)"
  if sudo cp "$file" "$backup"; then
    echo "$backup"
    return 0
  fi

  return 1
}

ssh__restore_backup() {
  local backup="$1"
  local original="${backup%.tgdb.bak.*}"

  if [ -z "$backup" ] || [ ! -f "$backup" ]; then
    return 1
  fi

  sudo cp "$backup" "$original" >/dev/null 2>&1
}

ssh__is_dropin_supported() {
  if [ ! -f "$SSH_SSHD_CONFIG" ]; then
    return 1
  fi

  # 僅判斷是否存在「未註解」的 Include /etc/ssh/sshd_config.d/...
  sudo grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSH_SSHD_CONFIG" 2>/dev/null
}

ssh__ensure_tgdb_dropin_file() {
  sudo mkdir -p "$SSH_TGDB_SSHD_DROPIN_DIR" >/dev/null 2>&1 || return 1
  if [ -f "$SSH_TGDB_SSHD_DROPIN_FILE" ]; then
    return 0
  fi

  cat <<'EOF' | sudo tee "$SSH_TGDB_SSHD_DROPIN_FILE" >/dev/null
# TGDB 管理設定（自動生成）
# 建議透過 TGDB 的「SSH 服務與登入安全」選單調整；手動修改可能造成設定不一致或被覆寫。
EOF
}

ssh__set_sshd_option_in_file() {
  local file="$1"
  local key="$2"
  local value="$3"

  if [ ! -f "$file" ]; then
    return 1
  fi

  if sudo grep -qiE "^[[:space:]]*${key}[[:space:]]+" "$file" 2>/dev/null; then
    sudo sed -i "s/^[[:space:]]*${key}[[:space:]]\\+.*/${key} ${value}/I" "$file" >/dev/null 2>&1 || return 1
    return 0
  fi

  echo "${key} ${value}" | sudo tee -a "$file" >/dev/null 2>&1 || return 1
  return 0
}

ssh__remove_sshd_option_in_file() {
  local file="$1"
  local key="$2"

  if [ ! -f "$file" ]; then
    return 1
  fi

  sudo sed -i "/^[[:space:]]*${key}[[:space:]]\\+/Id" "$file" >/dev/null 2>&1
}

ssh__oldest_backup_for_file() {
  local file="$1"

  # 以檔名時間戳記排序（YYYYMMDD-HHMMSS），取最舊的一份備份，通常代表「TGDB 第一次介入前」。
  sudo sh -c 'ls -1 "$1".tgdb.bak.* 2>/dev/null | LC_ALL=C sort | head -n1' sh "$file"
}

ssh__target_file_for_option() {
  local key="$1"

  # Port 可能是多實例選項；為了符合「直接替換」的預期，固定修改主設定檔。
  if [ "$key" = "Port" ]; then
    echo "$SSH_SSHD_CONFIG"
    return 0
  fi

  if ssh__is_dropin_supported; then
    echo "$SSH_TGDB_SSHD_DROPIN_FILE"
    return 0
  fi

  echo "$SSH_SSHD_CONFIG"
}

ssh__sshd_effective_value() {
  local key="$1"
  local out=""

  local sshd_bin
  sshd_bin="$(ssh__sshd_bin)" || return 1

  if [ -z "$sshd_bin" ]; then
    return 1
  fi

  # 使用 -C 讓 sshd 能在含 Match 的情境下輸出較接近實際的結果
  out=$(
    sudo "$sshd_bin" -T \
      -C "user=$(whoami)" \
      -C "host=$(hostname 2>/dev/null || echo localhost)" \
      -C "addr=127.0.0.1" 2>/dev/null | awk -v k="$key" '$1 == k { print $2; exit }'
  )

  if [ -n "$out" ]; then
    echo "$out"
    return 0
  fi

  return 1
}

ssh__sshd_effective_values() {
  # 取得 sshd -T 的「某 key 後面全部值」（例如 authorizedkeysfile 可能有多個 path）
  local key="$1"

  local sshd_bin
  sshd_bin="$(ssh__sshd_bin)" || return 1

  sudo "$sshd_bin" -T \
    -C "user=$(whoami)" \
    -C "host=$(hostname 2>/dev/null || echo localhost)" \
    -C "addr=127.0.0.1" 2>/dev/null \
    | awk -v k="$key" '$1 == k { $1=""; sub(/^ /,""); print; exit }'
}

ssh__get_kbdinteractive_directive() {
  # 以 sshd -T 的輸出為準：能取得值就代表該選項在此版本存在且可用。
  local value
  value="$(ssh__sshd_effective_value "kbdinteractiveauthentication" || echo "")"
  if [ -n "$value" ]; then
    echo "KbdInteractiveAuthentication"
    return 0
  fi

  value="$(ssh__sshd_effective_value "challengeresponseauthentication" || echo "")"
  if [ -n "$value" ]; then
    echo "ChallengeResponseAuthentication"
    return 0
  fi

  return 1
}

ssh__test_sshd_config() {
  local sshd_bin
  sshd_bin="$(ssh__sshd_bin 2>/dev/null || echo "")"
  if [ -z "$sshd_bin" ]; then
    tgdb_warn "系統中未找到 sshd 指令，略過語法檢查。"
    return 0
  fi

  if sudo "$sshd_bin" -t >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

ssh__reload_sshd() {
  if command -v systemctl >/dev/null 2>&1; then
    if sudo systemctl reload sshd >/dev/null 2>&1 || sudo systemctl reload ssh >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v service >/dev/null 2>&1; then
    if sudo service sshd reload >/dev/null 2>&1 || sudo service ssh reload >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1
}

ssh__apply_sshd_options() {
  # usage: ssh__apply_sshd_options Key1 Value1 [Key2 Value2 ...]
  if [ $(( $# % 2 )) -ne 0 ]; then
    tgdb_fail "內部錯誤：sshd 設定參數數量不正確。" 1 || true
    return 1
  fi

  if [ ! -f "$SSH_SSHD_CONFIG" ]; then
    tgdb_fail "找不到 SSH 設定檔：$SSH_SSHD_CONFIG" 1 || true
    return 1
  fi

  local -a files=()
  local -a backups=()

  local i key value target found existing idx
  i=1
  while [ "$i" -le "$#" ]; do
    key="${!i}"
    i=$((i + 1))
    value="${!i}"
    i=$((i + 1))

    target="$(ssh__target_file_for_option "$key")"
    if [ "$target" = "$SSH_TGDB_SSHD_DROPIN_FILE" ]; then
      if ! ssh__ensure_tgdb_dropin_file; then
        tgdb_fail "無法建立 SSH drop-in 設定檔：$SSH_TGDB_SSHD_DROPIN_FILE" 1 || true
        return 1
      fi
    fi

    found="0"
    for existing in "${files[@]}"; do
      if [ "$existing" = "$target" ]; then
        found="1"
        break
      fi
    done

    if [ "$found" = "0" ]; then
      files+=("$target")
      backups+=("$(ssh__backup_file "$target" || echo "")")
      local last_backup_index=$(( ${#backups[@]} - 1 ))
      if [ -z "${backups[$last_backup_index]}" ]; then
        tgdb_fail "無法備份 SSH 設定檔：$target" 1 || true
        return 1
      fi
    fi
  done

  i=1
  while [ "$i" -le "$#" ]; do
    key="${!i}"
    i=$((i + 1))
    value="${!i}"
    i=$((i + 1))

    target="$(ssh__target_file_for_option "$key")"
    if ! ssh__set_sshd_option_in_file "$target" "$key" "$value"; then
      tgdb_fail "無法寫入 SSH 設定：${key} ${value}" 1 || true
      for idx in "${!backups[@]}"; do
        [ -n "${backups[$idx]}" ] && ssh__restore_backup "${backups[$idx]}"
      done
      return 1
    fi
  done

  if ! ssh__test_sshd_config; then
    tgdb_fail "sshd 設定語法檢查失敗，已嘗試還原變更。" 1 || true
    for idx in "${!backups[@]}"; do
      [ -n "${backups[$idx]}" ] && ssh__restore_backup "${backups[$idx]}"
    done
    return 1
  fi

  if ssh__reload_sshd; then
    echo "✅ SSH 服務已重新載入。"
    return 0
  fi

  tgdb_warn "無法自動重新載入 SSH 服務，請手動重啟 sshd。"
  return 0
}

ssh_is_password_auth_enabled() {
  # ⚠️ 歷史相容：此函式名稱保留，但語意改為「是否仍存在任何密碼/互動式登入」。
  # PasswordAuthentication=yes 或 KbdInteractiveAuthentication(ChallengeResponse)=yes 皆視為「仍可用」。

  local password_auth
  password_auth="$(ssh__sshd_effective_value "passwordauthentication" || echo "")"
  password_auth="${password_auth,,}"
  if [ -z "$password_auth" ] && [ -f "$SSH_SSHD_CONFIG" ]; then
    password_auth="$(sudo grep -Ei "^[[:space:]]*PasswordAuthentication[[:space:]]+" "$SSH_SSHD_CONFIG" 2>/dev/null | tail -n1 | awk '{print $2}')"
    password_auth="${password_auth,,}"
  fi

  local kbd_key kbd_value
  kbd_key="$(ssh__get_kbdinteractive_directive 2>/dev/null || echo "")"
  kbd_value=""
  if [ "$kbd_key" = "KbdInteractiveAuthentication" ]; then
    kbd_value="$(ssh__sshd_effective_value "kbdinteractiveauthentication" || echo "")"
  elif [ "$kbd_key" = "ChallengeResponseAuthentication" ]; then
    kbd_value="$(ssh__sshd_effective_value "challengeresponseauthentication" || echo "")"
  fi
  kbd_value="${kbd_value,,}"

  if [ -z "$kbd_value" ] && [ -f "$SSH_SSHD_CONFIG" ]; then
    kbd_value="$(sudo grep -Ei "^[[:space:]]*(KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]+" "$SSH_SSHD_CONFIG" 2>/dev/null | tail -n1 | awk '{print $2}')"
    kbd_value="${kbd_value,,}"
  fi

  # 無法判斷時，保守視為「仍允許」，避免誤判導致流程（例如建立用戶）走錯分支。
  if [ -z "$password_auth" ] && [ -z "$kbd_value" ]; then
    return 0
  fi

  if [ "${password_auth:-yes}" = "yes" ] || [ "${kbd_value:-yes}" = "yes" ]; then
    return 0
  fi

  return 1
}

ensure_ssh_keygen_available() {
  if command -v ssh-keygen >/dev/null 2>&1; then
    return 0
  fi

  echo "未偵測到 ssh-keygen，正在嘗試安裝 OpenSSH 客戶端..."

  if ! pkg_install_role "ssh-client"; then
    tgdb_fail "系統無法自動安裝 ssh-keygen，請手動安裝 OpenSSH 客戶端。" 1 || true
    return 1
  fi

  command -v ssh-keygen >/dev/null 2>&1
}

ensure_admin_user_exists() {
  local admin_group
  admin_group=$(get_admin_group)

  if ! getent group "$admin_group" >/dev/null 2>&1; then
    tgdb_warn "系統中未找到管理員群組 '$admin_group'，無法自動檢查 sudo 用戶。"
    return 0
  fi

  local admin_users=()
  local username uid
  while IFS=: read -r username _ uid _; do
    if [ "$uid" -ge 1000 ] && id -nG "$username" 2>/dev/null | grep -qw "$admin_group"; then
      if [ "$username" != "root" ]; then
        admin_users+=("$username")
      fi
    fi
  done < <(getent passwd)

  if [ ${#admin_users[@]} -gt 0 ]; then
    echo "✅ 已偵測到具 sudo 權限的用戶：${admin_users[*]}"
    return 0
  fi

  tgdb_warn "系統中尚未發現具 sudo 權限的非 root 用戶。"
  echo "為避免鎖死系統，請先創建至少一個管理員用戶。"
  pause

  create_new_user

  admin_users=()
  username=""
  uid=""
  while IFS=: read -r username _ uid _; do
    if [ "$uid" -ge 1000 ] && id -nG "$username" 2>/dev/null | grep -qw "$admin_group"; then
      if [ "$username" != "root" ]; then
        admin_users+=("$username")
      fi
    fi
  done < <(getent passwd)

  if [ ${#admin_users[@]} -eq 0 ]; then
    tgdb_fail "仍未偵測到具 sudo 權限的用戶，暫停 root 登入相關變更。" 1 || true
    return 1
  fi

  echo "✅ 已建立或偵測到管理員用戶：${admin_users[*]}"
  return 0
}

ssh__ensure_any_sudo_user_has_authorized_keys() {
  local admin_group
  admin_group="$(get_admin_group)"

  if ! getent group "$admin_group" >/dev/null 2>&1; then
    tgdb_fail "無法確認 sudo 群組（$admin_group）是否存在，為避免鎖死，已拒絕禁用密碼登入。" 1 || true
    echo "請先確認系統的 sudo 群組設定，或改用主機控制台（VPS Console）操作。"
    return 1
  fi

  local sudo_users=()
  local username uid
  while IFS=: read -r username _ uid _; do
    if [ "$username" = "root" ]; then
      continue
    fi
    if [ "$uid" -lt 1000 ]; then
      continue
    fi
    if id -nG "$username" 2>/dev/null | grep -qw "$admin_group"; then
      sudo_users+=("$username")
    fi
  done < <(getent passwd)

  if [ ${#sudo_users[@]} -eq 0 ]; then
    tgdb_fail "尚未偵測到任何具 sudo 權限的非 root 用戶，為避免鎖死，已拒絕禁用密碼登入。" 1 || true
    echo "請先建立一個管理員用戶並設定 SSH 金鑰登入。"
    return 1
  fi

  local u
  for u in "${sudo_users[@]}"; do
    if ssh__authorized_keys_has_any_key "$u"; then
      return 0
    fi
  done

  tgdb_fail "未偵測到任何具 sudo 權限的非 root 用戶已設定 SSH 公鑰（authorized_keys 仍為空）。" 1 || true
  echo "偵測到的 sudo 用戶：${sudo_users[*]}"
  echo ""
  echo "請先用其中一個用戶登入後，在『SSH 服務與登入安全』執行："
  echo "1) 匯入現有公鑰（推薦，高安全）"
  echo "或"
  echo "2) 伺服器產生 Ed25519 金鑰（私鑰終端顯示一次）"
  echo ""
  echo "完成後再回來禁用密碼登入。"
  return 1
}

ssh__user_home() {
  local user="$1"
  getent passwd "$user" | cut -d: -f6
}

ssh__ensure_authorized_keys() {
  local user="$1"
  local home
  home="$(ssh__user_home "$user")"

  if [ -z "$home" ] || [ ! -d "$home" ]; then
    tgdb_fail "無法取得用戶 '$user' 的主目錄。" 1 || true
    return 1
  fi

  if ! sudo mkdir -p "$home/.ssh"; then
    tgdb_fail "無法建立 $home/.ssh 目錄。" 1 || true
    return 1
  fi

  sudo chmod 700 "$home/.ssh" >/dev/null 2>&1 || true
  if ! sudo touch "$home/.ssh/authorized_keys"; then
    tgdb_fail "無法建立 authorized_keys 檔案。" 1 || true
    return 1
  fi

  sudo chmod 600 "$home/.ssh/authorized_keys" >/dev/null 2>&1 || true
  sudo chown "$user":"$user" "$home/.ssh" "$home/.ssh/authorized_keys" >/dev/null 2>&1 || true
  return 0
}

ssh__authorized_keys_file() {
  local user="$1"
  local home
  home="$(ssh__user_home "$user")"
  echo "$home/.ssh/authorized_keys"
}

ssh__authorized_keys_files_for_user() {
  # 回傳以空白分隔的 authorized keys 檔案清單（依 sshd -T: authorizedkeysfile）
  local user="$1"
  local home
  home="$(ssh__user_home "$user")"
  if [ -z "$home" ]; then
    return 1
  fi

  local raw
  raw="$(ssh__sshd_effective_values "authorizedkeysfile" 2>/dev/null || echo "")"
  if [ -z "$raw" ]; then
    echo "$home/.ssh/authorized_keys"
    return 0
  fi

  local -a tokens=()
  # shellcheck disable=SC2206 # authorizedkeysfile 的值不含引號，直接 split 即可
  tokens=($raw)

  local -a out=()
  local t path
  for t in "${tokens[@]}"; do
    [ -z "$t" ] && continue
    if [ "$t" = "none" ]; then
      continue
    fi

    # 展開 sshd token（常見：%u / %h / %%）
    t="${t//%u/$user}"
    t="${t//%h/$home}"
    t="${t//%%/%}"

    if [[ "$t" = /* ]]; then
      path="$t"
    else
      path="${home%/}/$t"
    fi
    out+=("$path")
  done

  if [ ${#out[@]} -eq 0 ]; then
    echo "$home/.ssh/authorized_keys"
    return 0
  fi

  printf '%s\n' "${out[*]}"
}

ssh__authorized_keys_has_any_key() {
  local user="$1"
  local files
  files="$(ssh__authorized_keys_files_for_user "$user" 2>/dev/null || echo "")"
  if [ -z "$files" ]; then
    files="$(ssh__authorized_keys_file "$user")"
  fi

  local file
  for file in $files; do
    if [ ! -f "$file" ]; then
      continue
    fi

    if [ -r "$file" ]; then
      awk '
        /^[[:space:]]*#/ { next }
        NF == 0 { next }
        {
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^(ssh-|ecdsa-sha2-|sk-ssh-)/) {
              found = 1
              exit
            }
          }
        }
        END { exit(found ? 0 : 1) }
      ' "$file" >/dev/null 2>&1
      return $?
    fi

    # 若檔案對目前使用者不可讀，才用 sudo 嘗試（避免因 sudo 權限/提示被誤判為「檔案為空」）
    sudo awk '
      /^[[:space:]]*#/ { next }
      NF == 0 { next }
      {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^(ssh-|ecdsa-sha2-|sk-ssh-)/) {
            found = 1
            exit
          }
        }
      }
      END { exit(found ? 0 : 1) }
    ' "$file" >/dev/null 2>&1 && return 0
  done

  return 1
}

ssh__normalize_pubkey_line() {
  local line="$1"
  line="${line//$'\r'/}"
  echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

ssh__validate_pubkey_line() {
  local line="$1"

  # 基本格式：<type> <base64> [comment...]
  # 類型保守放寬，避免擋到 sk/ecdsa 等。
  if ! echo "$line" | awk 'NF>=2 { exit 0 } { exit 1 }' >/dev/null 2>&1; then
    return 1
  fi

  local key_type key_data
  key_type="$(echo "$line" | awk '{print $1}')"
  key_data="$(echo "$line" | awk '{print $2}')"

  if [ -z "$key_type" ] || [ -z "$key_data" ]; then
    return 1
  fi

  if ! echo "$key_type" | grep -Eq '^(ssh-|ecdsa-sha2-|sk-ssh-)'; then
    return 1
  fi

  return 0
}

ssh__append_authorized_key() {
  local user="$1"
  local pubkey_line="$2"

  if ! ssh__ensure_authorized_keys "$user"; then
    return 1
  fi

  pubkey_line="$(ssh__normalize_pubkey_line "$pubkey_line")"
  if [ -z "$pubkey_line" ]; then
    tgdb_fail "公鑰內容不可為空。" 1 || true
    return 1
  fi

  if ! ssh__validate_pubkey_line "$pubkey_line"; then
    tgdb_fail "公鑰格式看起來不正確，請確認是完整的一行 public key。" 1 || true
    return 1
  fi

  local file key_data
  file="$(ssh__authorized_keys_file "$user")"
  key_data="$(echo "$pubkey_line" | awk '{print $2}')"

  if sudo awk '{print $2}' "$file" 2>/dev/null | grep -qx "$key_data"; then
    echo "ℹ️ 此公鑰已存在於 $file，略過寫入。"
    return 0
  fi

  echo "$pubkey_line" | sudo tee -a "$file" >/dev/null 2>&1 || return 1
  sudo chown "$user":"$user" "$file" >/dev/null 2>&1 || true
  return 0
}

ssh__enable_pubkey_auth_if_needed() {
  local pubkey_auth
  pubkey_auth="$(ssh__sshd_effective_value "pubkeyauthentication" || echo "")"
  pubkey_auth="${pubkey_auth,,}"

  if [ "$pubkey_auth" = "yes" ]; then
    return 0
  fi

  echo ""
  tgdb_warn "偵測到目前 sshd 可能未啟用公鑰登入（PubkeyAuthentication=$pubkey_auth）。"
  if ! system_admin_confirm_yn "是否要啟用公鑰登入（PubkeyAuthentication yes）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    echo "已取消。"
    return 1
  fi

  ssh__apply_sshd_options "PubkeyAuthentication" "yes"
}

add_user_ssh_key_login_core() {
  local target_user="$1"

  if ! ensure_ssh_keygen_available; then
    pause
    return
  fi

  if [ -z "$target_user" ]; then
    tgdb_err "目標用戶不可為空。"
    pause
    return
  fi

  local target_home
  target_home="$(ssh__user_home "$target_user")"
  if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
    tgdb_err "無法取得用戶 '$target_user' 的主目錄。"
    pause
    return
  fi

  local ts tmp_dir priv_key_file pub_key_file
  ts="$(ssh__timestamp)"
  tmp_dir="$(mktemp -d /tmp/tgdb-user-key-XXXXXX 2>/dev/null || echo "")"
  if [ -z "$tmp_dir" ] || [ ! -d "$tmp_dir" ]; then
    tgdb_fail "無法建立暫存目錄用於產生 SSH 金鑰。" 1 || true
    pause
    return
  fi

  priv_key_file="$tmp_dir/${target_user}_ssh_key_${ts}"
  pub_key_file="${priv_key_file}.pub"

  echo ""
  echo "請為此金鑰輸入註記（例如：your_email@example.com 或 'tgdb-${target_user}@$(hostname)'）。"
  echo "直接按 Enter 可使用預設註記：tgdb-${target_user}-$(hostname)-${ts}"
  local key_comment
  read -r -e -p "金鑰註記: " key_comment
  if [ -z "$key_comment" ]; then
    key_comment="tgdb-${target_user}-$(hostname)-${ts}"
  fi

  echo ""
  echo "正在為用戶 '$target_user' 產生新的 Ed25519 SSH 金鑰..."
  echo "（稍後會提示設定金鑰密碼，建議設定強密碼）"
  if ! ssh-keygen -t ed25519 -a 64 -C "$key_comment" -f "$priv_key_file"; then
    tgdb_fail "產生 SSH 金鑰失敗。" 1 || true
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    pause
    return
  fi

  chmod 600 "$priv_key_file" >/dev/null 2>&1 || true

  echo ""
  echo "✅ 已為用戶 '$target_user' 產生 SSH 金鑰。"
  tgdb_warn "下方顯示的私鑰內容僅會顯示一次，且暫存在伺服器的暫存目錄。"
  echo "   高安全需求建議改用『本地產生金鑰 → 只匯入公鑰』。"
  echo ""
  echo "-----  請立即備份以下私鑰內容  -----"
  cat "$priv_key_file"
  echo "----------------------------------"
  echo ""
  if ! system_admin_confirm_yn "請確認已妥善保存私鑰後再繼續安裝公鑰，是否繼續？(y/N，預設 N，輸入 0 取消): " "N"; then
    echo "操作已取消，不會變更 SSH 設定。"
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    pause
    return
  fi

  echo ""
  echo "正在將公鑰安裝到 $target_user 的 ~/.ssh/authorized_keys..."
  if ! ssh__append_authorized_key "$target_user" "$(cat "$pub_key_file" 2>/dev/null)"; then
    tgdb_fail "無法寫入用戶 '$target_user' 的 authorized_keys。" 1 || true
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    pause
    return
  fi

  rm -rf "$tmp_dir" >/dev/null 2>&1 || true

  ssh__enable_pubkey_auth_if_needed || true

  echo ""
  echo "✅ 已為用戶 '$target_user' 啟用 SSH 金鑰登入。"
  echo "例如：ssh -i /path/to/your_saved_key ${target_user}@<server> -p <ssh_port>"
}

ssh_import_public_key_for_user() {
  local target_user="$1"

  if [ -z "$target_user" ]; then
    tgdb_err "目標用戶不可為空。"
    pause
    return
  fi

  local target_home
  target_home="$(ssh__user_home "$target_user")"
  if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
    tgdb_err "無法取得用戶 '$target_user' 的主目錄。"
    pause
    return
  fi

  while true; do
    maybe_clear
    echo "=================================="
    echo "❖ 匯入現有公鑰（$target_user） ❖"
    echo "=================================="
    echo "高安全需求建議：在本地產生金鑰後，只把公鑰匯入伺服器。"
    echo "----------------------------------"
    echo "1. 直接貼上單行公鑰"
    echo "2. 從檔案匯入（每行一把 key，會略過重複）"
    echo "0. 返回"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-2]: " choice

    case "$choice" in
      1)
        echo ""
        echo "請貼上完整的一行公鑰，例如：ssh-ed25519 AAAA... comment"
        local pubkey
        read -r -p "公鑰: " pubkey
        if ! ssh__append_authorized_key "$target_user" "$pubkey"; then
          pause
          return
        fi
        ssh__enable_pubkey_auth_if_needed || true
        echo "✅ 已匯入公鑰到 $target_user。"
        pause
        return
        ;;
      2)
        echo ""
        local key_file
        read -r -e -p "請輸入公鑰檔案路徑: " key_file
        if [ -z "$key_file" ] || [ ! -f "$key_file" ]; then
          tgdb_err "找不到檔案：$key_file"
          pause
          continue
        fi

        local imported=0 failed=0 line
        while IFS= read -r line; do
          line="$(ssh__normalize_pubkey_line "$line")"
          [ -z "$line" ] && continue
          echo "$line" | grep -qE '^[[:space:]]*#' && continue
          if ssh__append_authorized_key "$target_user" "$line"; then
            imported=$((imported + 1))
          else
            failed=$((failed + 1))
          fi
        done <"$key_file"

        ssh__enable_pubkey_auth_if_needed || true
        echo ""
        echo "完成：已嘗試匯入 $imported 筆（失敗 $failed 筆）。"
        pause
        return
        ;;
      0)
        return
        ;;
      *)
        echo "無效選項。"
        sleep 1
        ;;
    esac
  done
}

add_user_ssh_key_login() {
  maybe_clear
  echo "=================================="
  echo "❖ 為當前用戶新增 SSH 金鑰登入 ❖"
  echo "=================================="
  echo "預設流程：伺服器端產生 Ed25519 金鑰，並將公鑰安裝到 ~/.ssh/authorized_keys。"
  echo "高安全需求建議：改用『匯入現有公鑰』。"
  echo ""

  local target_user
  target_user="$(whoami)"
  add_user_ssh_key_login_core "$target_user"
  pause
}

add_user_ssh_key_login_for_user() {
  local new_user="$1"
  add_user_ssh_key_login_core "$new_user"
}

ssh__print_effective_status() {
  local port pw root pubkey
  port="$(ssh__sshd_effective_value "port" || echo "")"
  pw="$(ssh__sshd_effective_value "passwordauthentication" || echo "")"
  root="$(ssh__sshd_effective_value "permitrootlogin" || echo "")"
  pubkey="$(ssh__sshd_effective_value "pubkeyauthentication" || echo "")"

  echo "----------------------------------"
  echo "生效設定（以 sshd -T 為準；含 Include/部分 Match）"
  echo "Port: ${port:-未知}"
  echo "PubkeyAuthentication: ${pubkey:-未知}"
  echo "PasswordAuthentication: ${pw:-未知}"
  local kbd_value challenge_value
  kbd_value="$(ssh__sshd_effective_value "kbdinteractiveauthentication" || echo "")"
  challenge_value="$(ssh__sshd_effective_value "challengeresponseauthentication" || echo "")"
  if [ -n "$kbd_value" ]; then
    echo "KbdInteractiveAuthentication: ${kbd_value}"
  elif [ -n "$challenge_value" ]; then
    echo "ChallengeResponseAuthentication: ${challenge_value}"
  else
    echo "KbdInteractiveAuthentication/ChallengeResponseAuthentication: 未知（sshd -T 未輸出）"
  fi
  echo "PermitRootLogin: ${root:-未知}"
  echo "----------------------------------"
}

ssh_toggle_password_login() {
  maybe_clear
  echo "=================================="
  echo "❖ 密碼登入開關（Password/KbdInteractive） ❖"
  echo "=================================="

  local enabled="0"
  if ssh_is_password_auth_enabled; then
    enabled="1"
  fi

  if [ "$enabled" = "1" ]; then
    echo "目前狀態：✅ 仍允許密碼/互動式登入"
    echo ""
    tgdb_warn "即將禁用密碼登入（同時禁用 KbdInteractive/ChallengeResponse）。"
    tgdb_warn "建議先確保至少一個 sudo 用戶已能用 SSH 金鑰登入，避免鎖死。"
    echo ""

    if ! ensure_admin_user_exists; then
      echo "為避免鎖死系統，已取消操作。"
      pause
      return
    fi

    if ! ssh__ensure_any_sudo_user_has_authorized_keys; then
      pause
      return
    fi

    if ! system_admin_confirm_yn "確認要禁用密碼登入嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      echo "操作已取消。"
      pause
      return
    fi

    local kbd_directive
    kbd_directive="$(ssh__get_kbdinteractive_directive 2>/dev/null || echo "")"
    if [ -z "$kbd_directive" ]; then
      tgdb_warn "無法判斷要使用的 KbdInteractiveAuthentication/ChallengeResponseAuthentication 指令，將只禁用 PasswordAuthentication。"
      if ! ssh__apply_sshd_options "PasswordAuthentication" "no" "PubkeyAuthentication" "yes"; then
        pause
        return
      fi
    else
      if ! ssh__apply_sshd_options "PasswordAuthentication" "no" "$kbd_directive" "no" "PubkeyAuthentication" "yes"; then
        pause
        return
      fi
    fi

    echo ""
    echo "✅ 已禁用密碼登入。"
    pause
    return
  fi

  echo "目前狀態：✅ 已禁用密碼/互動式登入"
  echo ""
  tgdb_warn "即將啟用密碼登入（同時啟用 KbdInteractive/ChallengeResponse）。"
  tgdb_warn "這會增加暴力破解風險，建議搭配 Fail2Ban 與強密碼。"
  echo ""

  if ! system_admin_confirm_yn "確認要啟用密碼登入嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
    echo "操作已取消。"
    pause
    return
  fi

  local kbd_directive
  kbd_directive="$(ssh__get_kbdinteractive_directive 2>/dev/null || echo "")"
  if [ -z "$kbd_directive" ]; then
    tgdb_warn "無法判斷要使用的 KbdInteractiveAuthentication/ChallengeResponseAuthentication 指令，將只啟用 PasswordAuthentication。"
    if ! ssh__apply_sshd_options "PasswordAuthentication" "yes"; then
      pause
      return
    fi
  else
    if ! ssh__apply_sshd_options "PasswordAuthentication" "yes" "$kbd_directive" "yes"; then
      pause
      return
    fi
  fi

  echo ""
  echo "✅ 已啟用密碼登入。"
  pause
}

ssh_toggle_root_login() {
  maybe_clear
  echo "=================================="
  echo "❖ root SSH 登入開關 ❖"
  echo "=================================="

  local permit_root
  permit_root="$(ssh__sshd_effective_value "permitrootlogin" || echo "")"
  permit_root="${permit_root,,}"

  if [ "$permit_root" = "no" ]; then
    echo "目前狀態：✅ 已禁止 root SSH 登入（PermitRootLogin=no）"
    echo ""
    tgdb_warn "你選擇的策略是『完全禁止 root SSH 登入』，一般情況不建議再開啟。"
    if ! system_admin_confirm_yn "仍要啟用 root SSH 登入嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
      echo "操作已取消。"
      pause
      return
    fi

    if ! ssh__apply_sshd_options "PermitRootLogin" "yes"; then
      pause
      return
    fi
    echo ""
    echo "✅ 已啟用 root SSH 登入。"
    pause
    return
  fi

  tgdb_warn "目前狀態：root SSH 仍可能允許（PermitRootLogin=${permit_root:-未知}）"
  echo ""
  echo "此操作將完全禁止 root 透過 SSH 登入（PermitRootLogin no）。"
  echo "為避免鎖死系統，執行前需要至少一個具 sudo 權限的非 root 用戶。"
  echo ""

  if ! ensure_admin_user_exists; then
    echo "為避免鎖死系統，已取消操作。"
    pause
    return
  fi

  if ! system_admin_confirm_yn "確認要禁止 root 的 SSH 登入嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    echo "操作已取消。"
    pause
    return
  fi

  if ! ssh__apply_sshd_options "PermitRootLogin" "no"; then
    pause
    return
  fi
  echo ""
  echo "✅ 已禁止 root SSH 登入。"
  pause
}

get_current_ssh_port() {
  local port=""

  if [ -f "$SSH_SSHD_CONFIG" ]; then
    port="$(sudo grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSH_SSHD_CONFIG" 2>/dev/null | tail -n1 | awk '{print $2}')"
  fi

  if [ -z "$port" ]; then
    port="22"
  fi

  echo "$port"
}

change_ssh_port() {
  maybe_clear

  if [ ! -f "$SSH_SSHD_CONFIG" ]; then
    tgdb_fail "找不到 SSH 設定檔：$SSH_SSHD_CONFIG" 1 || true
    pause
    return
  fi

  local current_port
  current_port="$(get_current_ssh_port)"

  echo "=================================="
  echo "❖ 更改 SSH 連接埠 ❖"
  echo "=================================="
  echo "目前 SSH 連接埠: $current_port"
  echo "建議使用 1024-65535 之間且不常見的埠號。"
  echo "若直接按 Enter，將預設使用 ${TGDB_SSH_DEFAULT_PORT}。"
  echo "=================================="

  local new_port status
  if ! new_port="$(prompt_port_number "請輸入新的 SSH 埠" "${TGDB_SSH_DEFAULT_PORT}")"; then
    status=$?
    if [ "$status" -eq 2 ]; then
      echo "操作已取消。"
    else
      tgdb_err "無法取得有效的 SSH 埠。"
    fi
    pause
    return
  fi

  if [ "$new_port" -eq "$current_port" ]; then
    echo "ℹ️ 新舊埠號相同，未做任何變更。"
    pause
    return
  fi

  if ssh_is_port_in_use "$new_port"; then
    tgdb_warn "埠 $new_port 目前已被其他服務使用。"
    if ! system_admin_confirm_yn "仍要使用此埠嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
      echo "操作已取消。"
      pause
      return
    fi
  fi

  echo ""
  tgdb_warn "警告：修改 SSH 埠後，遠端連線需要改用："
  echo "    ssh -p $new_port <user>@<server>" >&2
  echo "若目前是遠端連線，請先在另一個終端測試新埠可登入，再關閉舊連線。" >&2
  echo ""

  if ! system_admin_confirm_yn "確認要將 SSH 埠從 $current_port 改為 $new_port 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
    echo "操作已取消。"
    pause
    return
  fi

  # Port 直接改主設定檔（符合「直接替換」）
  if ! ssh__apply_sshd_options "Port" "$new_port"; then
    pause
    return
  fi

  echo ""
  echo "✅ SSH 連接埠已更新為：$new_port"

  # 自動嘗試同步 nftables 設定，避免 SSH 埠變更後被防火牆阻擋
  if [ -f "$SRC_DIR/nftables.sh" ]; then
    # shellcheck source=src/nftables.sh
    source "$SRC_DIR/nftables.sh"
    if declare -F nftables_update_ssh_port >/dev/null 2>&1; then
      echo ""
      echo "→ 偵測到 nftables 管理模組，正在嘗試更新防火牆 SSH 規則..."
      nftables_update_ssh_port "$current_port" "$new_port"
    else
      echo "ℹ️ 已載入 nftables 模組，但缺少 nftables_update_ssh_port，請視情況手動更新防火牆規則。"
    fi
  else
    echo "ℹ️ 找不到 nftables 管理模組，請手動確認防火牆規則是否已開放新 SSH 埠。"
  fi

  pause
}

change_ssh_port_cli() {
  local new_port="${TGDB_SSH_DEFAULT_PORT:-25252}"

  if [ ! -f "$SSH_SSHD_CONFIG" ]; then
    tgdb_fail "找不到 SSH 設定檔：$SSH_SSHD_CONFIG" 1 || true
    return 1
  fi

  local current_port
  if declare -F detect_ssh_port >/dev/null 2>&1; then
    current_port="$(detect_ssh_port)"
  else
    current_port="$(get_current_ssh_port)"
  fi

  echo "=================================="
  echo "❖ 更改 SSH 連接埠（CLI）❖"
  echo "=================================="
  echo "目前 SSH 連接埠: $current_port"
  echo "預設將設定為: $new_port"

  if [ "$new_port" -eq "$current_port" ] 2>/dev/null; then
    echo "ℹ️ 新舊埠號相同，未做任何變更。"
    return 0
  fi

  if ssh_is_port_in_use "$new_port"; then
    tgdb_fail "目標埠 $new_port 已被其他服務使用，為避免衝突已停止操作。" 1 || true
    return 1
  fi

  # 先嘗試放行新埠，避免套用 SSH 設定後被防火牆阻擋
  if [ -f "$SRC_DIR/nftables.sh" ]; then
    # shellcheck source=src/nftables.sh
    source "$SRC_DIR/nftables.sh"
    if declare -F nftables_update_ssh_port >/dev/null 2>&1; then
      echo "→ 偵測到 nftables 模組，嘗試先更新防火牆 SSH 規則..."
      if ! nftables_update_ssh_port "$current_port" "$new_port"; then
        tgdb_fail "無法自動更新防火牆 SSH 規則，為避免鎖死已停止變更 SSH 埠。" 1 || true
        return 1
      fi
    fi
  fi

  if ! ssh__apply_sshd_options "Port" "$new_port"; then
    return 1
  fi

  echo ""
  echo "✅ SSH 連接埠已更新為：$new_port"
  tgdb_warn "遠端連線需改用：ssh -p $new_port <user>@<server>"
  return 0
}

ssh_show_status() {
  maybe_clear
  echo "=================================="
  echo "❖ SSH 生效狀態檢視 ❖"
  echo "=================================="
  ssh__print_effective_status
  pause
}

ssh_restore_system_defaults() {
  maybe_clear
  echo "=================================="
  echo "❖ 恢復到系統預設（移除 TGDB SSH 設定） ❖"
  echo "=================================="
  tgdb_warn "重要提醒：此操作可能導致你目前的 SSH 連線中斷。"
  echo "請務必確認你有 VPS Console / 實體主機控制台等備援登入方式。" >&2
  echo ""

  if [ ! -f "$SSH_SSHD_CONFIG" ]; then
    tgdb_fail "找不到 SSH 設定檔：$SSH_SSHD_CONFIG" 1 || true
    pause
    return
  fi

  local dropin_exists="0"
  if [ -f "$SSH_TGDB_SSHD_DROPIN_FILE" ]; then
    dropin_exists="1"
  fi

  local sshd_oldest_backup
  sshd_oldest_backup="$(ssh__oldest_backup_for_file "$SSH_SSHD_CONFIG" 2>/dev/null || echo "")"

  echo "將執行以下動作："
  if [ "$dropin_exists" = "1" ]; then
    echo "- 刪除：$SSH_TGDB_SSHD_DROPIN_FILE"
  else
    echo "- 找不到：$SSH_TGDB_SSHD_DROPIN_FILE（略過）"
  fi

  if [ -n "$sshd_oldest_backup" ]; then
    echo "- 還原：$SSH_SSHD_CONFIG ← $sshd_oldest_backup"
  else
    echo "- 找不到 $SSH_SSHD_CONFIG 的 TGDB 備份，將改用『移除 TGDB 可能寫入的選項』方式嘗試恢復。"
    echo "  （將移除：Port / PermitRootLogin / PasswordAuthentication / KbdInteractiveAuthentication / ChallengeResponseAuthentication / PubkeyAuthentication）"
  fi

  echo ""
  if ! system_admin_confirm_yn "確認要繼續恢復到系統預設嗎？(y/N，預設 N，輸入 0 取消): " "N"; then
    echo "操作已取消。"
    pause
    return
  fi

  local pre_backup_sshd pre_backup_dropin
  pre_backup_sshd="$(ssh__backup_file "$SSH_SSHD_CONFIG" || echo "")"
  if [ -z "$pre_backup_sshd" ]; then
    tgdb_fail "無法備份目前的 $SSH_SSHD_CONFIG，已取消。" 1 || true
    pause
    return
  fi

  pre_backup_dropin=""
  if [ "$dropin_exists" = "1" ]; then
    pre_backup_dropin="$(ssh__backup_file "$SSH_TGDB_SSHD_DROPIN_FILE" || echo "")"
    if [ -z "$pre_backup_dropin" ]; then
      tgdb_fail "無法備份目前的 $SSH_TGDB_SSHD_DROPIN_FILE，已取消。" 1 || true
      pause
      return
    fi
  fi

  if [ -n "$sshd_oldest_backup" ]; then
    if ! sudo cp "$sshd_oldest_backup" "$SSH_SSHD_CONFIG" >/dev/null 2>&1; then
      tgdb_fail "還原 $SSH_SSHD_CONFIG 失敗，已取消。" 1 || true
      pause
      return
    fi
  else
    ssh__remove_sshd_option_in_file "$SSH_SSHD_CONFIG" "Port" || true
    ssh__remove_sshd_option_in_file "$SSH_SSHD_CONFIG" "PermitRootLogin" || true
    ssh__remove_sshd_option_in_file "$SSH_SSHD_CONFIG" "PasswordAuthentication" || true
    ssh__remove_sshd_option_in_file "$SSH_SSHD_CONFIG" "KbdInteractiveAuthentication" || true
    ssh__remove_sshd_option_in_file "$SSH_SSHD_CONFIG" "ChallengeResponseAuthentication" || true
    ssh__remove_sshd_option_in_file "$SSH_SSHD_CONFIG" "PubkeyAuthentication" || true
  fi

  if [ "$dropin_exists" = "1" ]; then
    if ! sudo rm -f "$SSH_TGDB_SSHD_DROPIN_FILE" >/dev/null 2>&1; then
      tgdb_fail "刪除 $SSH_TGDB_SSHD_DROPIN_FILE 失敗，已取消。" 1 || true
      ssh__restore_backup "$pre_backup_sshd" || true
      if [ -n "$pre_backup_dropin" ]; then
        ssh__restore_backup "$pre_backup_dropin" || true
      fi
      pause
      return
    fi
  fi

  if ! ssh__test_sshd_config; then
    tgdb_fail "sshd 設定語法檢查失敗，已自動還原到執行前狀態。" 1 || true
    ssh__restore_backup "$pre_backup_sshd" || true
    if [ -n "$pre_backup_dropin" ]; then
      ssh__restore_backup "$pre_backup_dropin" || true
    fi
    pause
    return
  fi

  if ssh__reload_sshd; then
    echo "✅ 已恢復到系統預設並重新載入 SSH。"
  else
    tgdb_warn "已恢復到系統預設，但無法自動重新載入 SSH，請手動重啟 sshd。"
  fi

  pause
}

manage_ssh() {
  while true; do
    maybe_clear

    local port pw_enabled permit_root
    port="$(ssh__sshd_effective_value "port" || get_current_ssh_port)"
    pw_enabled="禁用"
    if ssh_is_password_auth_enabled; then
      pw_enabled="啟用"
    fi

    permit_root="$(ssh__sshd_effective_value "permitrootlogin" || echo "未知")"

    echo "=================================="
    echo "❖ SSH 服務與登入安全 ❖"
    echo "=================================="
    echo "狀態摘要：Port=${port:-未知}｜密碼登入=${pw_enabled}｜PermitRootLogin=${permit_root:-未知}"
    echo "----------------------------------"
    echo "1. 檢視目前 SSH 生效設定"
    echo "2. 為當前用戶產生 Ed25519 金鑰並安裝（伺服器產生）"
    echo "3. 匯入現有公鑰到當前用戶（高安全需求推薦）"
    echo "4. 切換密碼登入（禁用/啟用，含 KbdInteractive）"
    echo "5. 切換 root SSH 登入（禁用/啟用）"
    echo "6. 更改 SSH 連接埠（預設 ${TGDB_SSH_DEFAULT_PORT}）"
    echo "7. 恢復到系統預設（移除 TGDB SSH 設定）"
    echo "----------------------------------"
    echo "0. 返回系統管理選單"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-7]: " ssh_choice

    case "$ssh_choice" in
      1)
        ssh_show_status
        ;;
      2)
        add_user_ssh_key_login
        ;;
      3)
        ssh_import_public_key_for_user "$(whoami)"
        ;;
      4)
        ssh_toggle_password_login
        ;;
      5)
        ssh_toggle_root_login
        ;;
      6)
        change_ssh_port
        ;;
      7)
        ssh_restore_system_defaults
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
