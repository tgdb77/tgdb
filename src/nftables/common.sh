#!/bin/bash

# nftables 共用與輔助函式
_nft_bin() {
    # 部分發行版會將 nft 安裝在 /usr/sbin（一般使用者 PATH 可能未包含），
    # 造成「服務已在跑，但工具判斷未安裝」的誤判，因此改用多路徑偵測。
    local p
    p="$(type -P nft 2>/dev/null || true)"
    if [ -n "${p:-}" ] && [ -x "$p" ]; then
        echo "$p"
        return 0
    fi

    for p in \
        /usr/sbin/nft \
        /usr/bin/nft \
        /sbin/nft \
        /bin/nft \
        /usr/local/sbin/nft \
        /usr/local/bin/nft \
        /run/current-system/sw/bin/nft \
        /nix/var/nix/profiles/default/bin/nft \
    ; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

_has_nft_cmd() {
    _nft_bin >/dev/null 2>&1 && return 0

    # 最後保險：sudo 通常會有 secure_path（含 /usr/sbin），
    # 即使目前使用者 PATH 找不到 nft，實際上仍可能已安裝且可透過 sudo 執行。
    if command -v sudo >/dev/null 2>&1; then
        sudo -n nft --version >/dev/null 2>&1 && return 0
    fi

    return 1
}

_nftables_init_paths() {
    if [ -z "${TGDB_DIR:-}" ]; then
        load_system_config || true
    fi
    if [ -z "${TGDB_DIR:-}" ]; then
        tgdb_fail "TGDB_DIR 未設定，無法初始化 nftables 備份路徑。" 1 || true
        return 1
    fi
    NFTABLES_BACKUP_DIR="${TGDB_DIR}/nftables"
    return 0
}

# 公用與輔助
ensure_backup_dir() {
    _nftables_init_paths || return 1
    if [ ! -d "$NFTABLES_BACKUP_DIR" ]; then
        mkdir -p "$NFTABLES_BACKUP_DIR" || {
            tgdb_fail "無法建立備份目錄: $NFTABLES_BACKUP_DIR" 1 || true
            return 1
        }
        if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
            chown "$(_detect_invoking_uid)":"$(_detect_invoking_gid)" "$NFTABLES_BACKUP_DIR" 2>/dev/null || true
        fi
        echo "✅ 已建立備份目錄: $NFTABLES_BACKUP_DIR"
    fi
    return 0
}


_tgdb_table_exists() {
    sudo nft list table inet tgdb_net >/dev/null 2>&1
}

# 內部：將當前 inet tgdb_net 規則集持久化到 /etc/nftables.conf
_persist_tgdb_table() {
    if _tgdb_table_exists; then
        if sudo nft -s list table inet tgdb_net | sudo tee /etc/nftables.conf >/dev/null; then
            if sudo nft -c -f /etc/nftables.conf >/dev/null 2>&1; then
                return 0
            else
                tgdb_warn "規則已套用但持久化檔驗證失敗，請檢查 /etc/nftables.conf"
                return 1
            fi
        else
            tgdb_warn "規則已套用但寫入 /etc/nftables.conf 失敗"
            return 1
        fi
    else
        tgdb_warn "尚未建立 table inet tgdb_net，請先執行初始化"
        return 1
    fi
}

# 內部：取得集合元素的一行摘要（如 80,443,1000-2000）。若無或不存在回傳「無」。
_get_set_elements_line() {
    local set_name="$1"
    local content
    content=$(sudo nft list set inet tgdb_net "$set_name" 2>/dev/null | \
        sed -n '/elements[[:space:]]*=.*/,/}/p' | tr -d '\n' | \
        sed -e 's/.*elements[[:space:]]*=[[:space:]]*{//' -e 's/}.*//' 2>/dev/null)
    if [ -n "$content" ]; then
        echo "$content" | sed 's/, /,/g' | xargs
    else
        echo "無"
    fi
}

# 內部：取得 PING 狀態（允許/禁止）
_get_ping_status() {
    local list_out
    list_out=$(sudo nft -a list chain inet tgdb_net input 2>/dev/null)
    if echo "$list_out" | awk '/ip protocol icmp/ && /echo-request/ && /drop/ {found=1} /icmpv6/ && /echo-request/ && /drop/ {found=1} END{exit(found?0:1)}'; then
        echo "禁止"
    else
        echo "允許"
    fi
}

# 內部：檢查是否存在「全開」規則（以 comment 標記）
_has_open_all_rule() {
    local out
    out=$(sudo nft -a list chain inet tgdb_net input 2>/dev/null)
    local has_tcp has_udp
    has_tcp=$(echo "$out" | grep -F "tgdb-open-all-tcp" >/dev/null 2>&1 && echo yes || echo no)
    has_udp=$(echo "$out" | grep -F "tgdb-open-all-udp" >/dev/null 2>&1 && echo yes || echo no)
    echo "$has_tcp,$has_udp"
}

# 內部：詢問協定（TCP/UDP），以數字選擇（1/2）
_prompt_tcp_udp_proto() {
    local out_var="$1"
    if [ -z "${out_var:-}" ]; then
        tgdb_fail "_prompt_tcp_udp_proto 參數不足：<out_var>" 1 || true
        return 1
    fi

    local idx
    echo "請選擇協定："
    echo "1. TCP"
    echo "2. UDP"
    if ! ui_prompt_index idx "請輸入選擇 [1-2] (預設 1，輸入 0 取消): " 1 2 1 0; then
        return $?
    fi

    case "$idx" in
        1) printf -v "$out_var" '%s' "tcp" ;;
        2) printf -v "$out_var" '%s' "udp" ;;
        *) return 1 ;;
    esac
    return 0
}

_parse_ip_family_and_value() {
    local input="$1"
    if [[ "$input" =~ : ]]; then
        echo "v6|$input"
        return 0
    else
        echo "v4|$input"
        return 0
    fi
}
