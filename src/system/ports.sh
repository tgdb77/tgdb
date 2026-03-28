#!/bin/bash

# 系統管理：連接埠工具
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -e）。

_ports_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_ports_print_listeners() {
    if command -v ss >/dev/null 2>&1; then
        if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
            ss -tulpn || true
        elif command -v sudo >/dev/null 2>&1; then
            sudo ss -tulpn || true
        else
            echo "⚠️  找不到 sudo，將以非 root 模式顯示（可能無法顯示 PID/程式名）。"
            ss -tuln || true
        fi
        return 0
    fi

    if command -v netstat >/dev/null 2>&1; then
        if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
            netstat -tulnp || true
        elif command -v sudo >/dev/null 2>&1; then
            sudo netstat -tulnp || true
        else
            echo "⚠️  找不到 sudo，將以非 root 模式顯示（可能無法顯示 PID/程式名）。"
            netstat -tuln || true
        fi
        return 0
    fi

    echo "未找到 ss 或 netstat，請安裝 iproute2 或 net-tools。"
    return 1
}

_ports_collect_podman_published_ports() {
    local container_name="$1"
    local ports="$2"
    local re_single=':([0-9]+)->([0-9]+)/(tcp|udp)$'
    local re_range=':([0-9]+)-([0-9]+)->([0-9]+)-([0-9]+)/(tcp|udp)$'

    ports="$(_ports_trim "$ports")"
    [ -n "$ports" ] || return 0
    [ "$ports" != "-" ] || return 0
    [ "$ports" != "N/A" ] || return 0

    local item
    local -a items=()
    IFS=',' read -r -a items <<< "$ports"
    for item in "${items[@]}"; do
        item="$(_ports_trim "$item")"

        # 常見格式：0.0.0.0:8080->80/tcp、[::]:8080->80/tcp、127.0.0.1:8080->80/tcp
        if [[ "$item" =~ $re_single ]]; then
            printf '%s\t%s\t%s\t%s\n' "${BASH_REMATCH[3]}" "${BASH_REMATCH[1]}" "$container_name" "${BASH_REMATCH[2]}"
            continue
        fi

        # 連接埠範圍：0.0.0.0:10000-10010->10000-10010/tcp
        if [[ "$item" =~ $re_range ]]; then
            printf '%s\t%s-%s\t%s\t%s-%s\n' "${BASH_REMATCH[5]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$container_name" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
            continue
        fi
    done
}

_ports_print_table() {
    if command -v column >/dev/null 2>&1; then
        column -t -s $'\t'
        return 0
    fi

    awk -F'\t' '
        NR == 1 {
            h1 = $1
            h2 = $2
            h3 = $3
            max1 = length($1)
            max2 = length($2)
            next
        }
        {
            rows[NR] = $0
            if (length($1) > max1) max1 = length($1)
            if (length($2) > max2) max2 = length($2)
        }
        END {
            fmt = "%-" max1 "s  %-" max2 "s  %s\n"
            printf fmt, h1, h2, h3
            for (i = 2; i <= NR; i++) {
                split(rows[i], a, FS)
                printf fmt, a[1], a[2], a[3]
            }
        }
    '
}

_ports_print_podman_port_map() {
    command -v podman >/dev/null 2>&1 || return 0

    local -a rows
    mapfile -t rows < <(podman ps --format "{{.Names}}\t{{.Ports}}" 2>/dev/null || true)
    if [ "${#rows[@]}" -eq 0 ]; then
        echo
        echo "----------------------------------"
        echo "Podman 容器對外連接埠對照（HostPort -> 容器:Port）"
        echo "目前未偵測到任何運行中的 Podman 容器（或無權限列出）。"
        echo "提示：若容器以其他使用者（root/rootless）執行，請切換到對應使用者後再查看。"
        return 0
    fi

    local -A port_map=()
    local -A seen=()

    local row container_name ports
    local -a entries=()

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r container_name ports <<< "$row"
        while IFS=$'\t' read -r proto host_port name container_port; do
            [ -n "$proto" ] || continue
            [ -n "$host_port" ] || continue
            [ -n "$name" ] || continue
            [ -n "$container_port" ] || continue

            local key="$proto|$host_port"
            local item_key="$proto|$host_port|$name|$container_port"
            if [ -n "${seen[$item_key]+x}" ]; then
                continue
            fi
            seen["$item_key"]=1

            if [ -n "${port_map[$key]:-}" ]; then
                port_map["$key"]="${port_map[$key]}, $name:$container_port"
            else
                port_map["$key"]="$name:$container_port"
            fi
        done < <(_ports_collect_podman_published_ports "$container_name" "$ports")
    done

    if [ "${#port_map[@]}" -eq 0 ]; then
        echo
        echo "----------------------------------"
        echo "Podman 容器對外連接埠對照（HostPort -> 容器:Port）"
        echo "目前未偵測到任何已發布到 Host 的連接埠（podman ps 的 Ports 欄位為空）。"
        return 0
    fi

    echo
    echo "----------------------------------"
    echo "Podman 容器對外連接埠對照（HostPort -> 容器:Port）"
    echo "提示：若上方 Process 顯示為 pasta/rootlessport，通常是 Rootless Podman 的轉發程序，可用此表反查容器名稱。"

    local k proto host_port
    for k in "${!port_map[@]}"; do
        proto="${k%%|*}"
        host_port="${k#*|}"
        entries+=("$proto"$'\t'"$host_port"$'\t'"${port_map[$k]}")
    done

    {
        printf '%s\t%s\t%s\n' "PROTO" "HOSTPORT" "CONTAINER:PORT"
        if [ "${#entries[@]}" -gt 0 ]; then
            printf '%s\n' "${entries[@]}" | sort -t$'\t' -k1,1 -k2,2n
        fi
    } | _ports_print_table
}

# 檢視連接埠佔用狀態
view_port_status() {
    maybe_clear
    echo "正在檢視所有監聽中的連接埠 (TCP 和 UDP)，並顯示使用該連接埠的進程（PID/程式名）..."
    _ports_print_listeners || true
    _ports_print_podman_port_map || true
    pause
}
