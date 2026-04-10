#!/bin/bash

# Podman：Quadlet Pod 相關輔助（找出 pod 基底/成員容器/停止 pod）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_pod_base_from_token() {
    local token="$1"
    local base=""

    if declare -F _podman_token_name >/dev/null 2>&1; then
        token="$(_podman_token_name "$token")"
    fi

    case "$token" in
        *.pod)
            base="${token%.pod}"
            ;;
        pod-*.service)
            base="${token#pod-}"
            base="${base%.service}"
            ;;
        podman-pod-*.service)
            base="${token#podman-pod-}"
            base="${base%.service}"
            ;;
        *-pod.service)
            base="${token%-pod.service}"
            ;;
        *)
            return 1
            ;;
    esac

    [ -n "$base" ] || return 1
    printf '%s\n' "$base"
}

_list_pod_member_container_unit_files_by_scope() {
    local scope="$1" pod_base="$2"
    [ -n "$pod_base" ] || return 0

    local dir
    dir="$(_podman_unit_dir "$scope")"
    [ -d "$dir" ] || return 0

    local -a files=()
    local f
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$dir" \( -type f -o -type l \) -name "*.container" -print0 2>/dev/null)

    for f in "${files[@]}"; do
        [ -r "$f" ] || continue
        if awk -v base="$pod_base" '
            BEGIN { found=0 }
            /^[[:space:]]*Pod[[:space:]]*=/ {
              line=$0
              sub(/^[[:space:]]*Pod[[:space:]]*=[[:space:]]*/, "", line)
              sub(/[[:space:]]*(#.*)?$/, "", line)
              gsub(/^"|"$/, "", line)
              gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
              if (line == base || line == base ".pod") { found=1; exit }
            }
            END { exit (found ? 0 : 1) }
          ' "$f"; then
            basename "$f"
        fi
    done | awk '!seen[$0]++'
}

_list_pod_member_container_unit_files() {
    _list_pod_member_container_unit_files_by_scope user "$1"
}

_container_name_from_unit_file() {
    local unit_file="$1"
    [ -r "$unit_file" ] || return 0
    awk '
        /^[[:space:]]*ContainerName[[:space:]]*=/ {
          line=$0
          sub(/^[[:space:]]*ContainerName[[:space:]]*=[[:space:]]*/, "", line)
          sub(/[[:space:]]*(#.*)?$/, "", line)
          gsub(/^"|"$/, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          if (line != "") { print line }
          exit
        }
      ' "$unit_file"
}

_unit_try_stop_pod_with_members() {
    local token="$1"

    local pod_base
    pod_base="$(_pod_base_from_token "$token")" || return 1

    local scope
    scope="$(_podman_token_scope "$token")"
    scope="${scope:-user}"

    local -a members=()
    mapfile -t members < <(_list_pod_member_container_unit_files_by_scope "$scope" "$pod_base")

    # 停止 Pod 時需同時停用/停止其成員容器，避免只停到其中一個 unit（同名 alias）造成殘留。
    # 先把「實際存在的 systemd units」收斂出來，再逐一 disable/stop。
    local -a units=()
    local u m

    while IFS= read -r u; do
        [ -n "$u" ] && units+=("$u")
    done < <(_podman_existing_action_units "$scope" "${pod_base}.pod" 2>/dev/null || true)

    for m in "${members[@]}"; do
        while IFS= read -r u; do
            [ -n "$u" ] && units+=("$u")
        done < <(_podman_existing_action_units "$scope" "$m" 2>/dev/null || true)
    done

    mapfile -t units < <(printf "%s\n" "${units[@]}" | awk 'NF && !seen[$0]++')

    local any=false
    for u in "${units[@]}"; do
        if _podman_systemctl "$scope" disable --now -- "$u" >/dev/null 2>&1; then
            any=true
            continue
        fi
        if _podman_systemctl "$scope" stop -- "$u" >/dev/null 2>&1; then
            any=true
        fi
    done

    if [ "$any" = true ]; then
        if [ "${#members[@]}" -gt 0 ]; then
            echo "✅ 已停止 Pod（並停用自動啟動）：$pod_base（成員容器：${#members[@]} 個）"
        else
            echo "✅ 已停止 Pod（並停用自動啟動）：$pod_base"
        fi
        return 0
    fi

    tgdb_warn "無法停止 Pod：$pod_base（可能找不到對應 systemd --user 單元）"
    return 1
}
