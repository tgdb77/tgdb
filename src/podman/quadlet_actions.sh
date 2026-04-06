#!/bin/bash

# Podman：Quadlet 動作（停止/查看日誌）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_unit_try_stop() {
    local token="$1"
    if [ -z "$token" ]; then
        tgdb_fail "單元名稱不可為空" 1 || return $?
    fi

    # Pod 特例：停止/停用整個 pod（含其成員容器）
    if _unit_try_stop_pod_with_members "$token"; then
        return 0
    fi

    local any=false scope name
    while IFS=$'\t' read -r scope name _; do
        [ -n "${scope:-}" ] || continue
        [ -n "${name:-}" ] || continue

        local -a units=()
        # 停止單元僅應針對「該單元類型」的 systemd unit，避免同名 pod/container 時誤停 pod。
        mapfile -t units < <(_podman_action_unit_candidates "$name" | awk 'NF && !seen[$0]++')
        [ "${#units[@]}" -gt 0 ] || continue

        if _podman_systemctl_try_candidates "$scope" disable --now -- "${units[@]}" >/dev/null 2>&1; then
            any=true
        elif _podman_systemctl_try_candidates "$scope" stop -- "${units[@]}" >/dev/null 2>&1; then
            any=true
        fi
    done < <(_resolve_unit_records "$token")

    if [ "$any" = true ]; then
        echo "✅ 已停止（並停用自動啟動）：$token"
        echo "提示：如要再次啟動，請使用「重新啟動單元」。"
        return 0
    fi

    tgdb_warn "無法停止單元：$token（可能找不到對應 systemd 單元）"
    return 1
}

_follow_unit_logs() {
    local scope="$1" label="$2"
    shift 2 || true
    local -a units=("$@")
    [ "${#units[@]}" -gt 0 ] || return 1

    clear
    echo "=================================="
    echo "❖ 實時查看單元日誌 ❖"
    echo "=================================="
    echo "範圍：$(_podman_scope_display_name "$scope")"
    echo "單元：$label"
    echo "顯示最近 200 行並持續追蹤。"
    echo "按 Ctrl+C 結束並返回上一層。"
    echo "----------------------------------"

    local -a journal_args=()
    local unit
    for unit in "${units[@]}"; do
        [ -n "$unit" ] || continue
        journal_args+=(-u "$unit")
    done
    [ "${#journal_args[@]}" -gt 0 ] || return 1

    trap ':' INT
    _podman_journalctl "$scope" "${journal_args[@]}" -n 200 -f --no-pager 2>/dev/null || true
    trap - INT
}

_unit_log_candidates() {
    local token="$1"
    local name ext

    _podman_split_unit_token "$token" name ext

    case "$ext" in
        service|timer|path|socket)
            printf '%s\n' "$token"
            ;;
        container)
            printf '%s\n' "$name.service"
            printf '%s\n' "container-$name.service"
            printf '%s\n' "podman-$name.service"
            printf '%s\n' "$token"
            ;;
        pod)
            printf '%s\n' "$name-pod.service"
            printf '%s\n' "pod-$name.service"
            printf '%s\n' "podman-pod-$name.service"
            printf '%s\n' "podman-$name-pod.service"
            printf '%s\n' "$token"
            ;;
        network)
            printf '%s\n' "network-$name.service"
            printf '%s\n' "$name-network.service"
            printf '%s\n' "podman-network-$name.service"
            printf '%s\n' "podman-$name-network.service"
            printf '%s\n' "$token"
            ;;
        volume)
            printf '%s\n' "volume-$name.service"
            printf '%s\n' "$name-volume.service"
            printf '%s\n' "podman-volume-$name.service"
            printf '%s\n' "podman-$name-volume.service"
            printf '%s\n' "$token"
            ;;
        kube)
            printf '%s\n' "kube-$name.service"
            printf '%s\n' "$name-kube.service"
            printf '%s\n' "podman-kube-$name.service"
            printf '%s\n' "podman-$name-kube.service"
            printf '%s\n' "$token"
            ;;
        image)
            printf '%s\n' "image-$name.service"
            printf '%s\n' "$name-image.service"
            printf '%s\n' "podman-image-$name.service"
            printf '%s\n' "podman-$name-image.service"
            printf '%s\n' "$token"
            ;;
        device)
            printf '%s\n' "device-$name.service"
            printf '%s\n' "$name-device.service"
            printf '%s\n' "podman-device-$name.service"
            printf '%s\n' "podman-$name-device.service"
            printf '%s\n' "$token"
            ;;
        *)
            _resolve_unit_candidates "$token"
            return 0
            ;;
    esac
}

_unit_try_logs_follow() {
    local token="$1"
    local scope name
    while IFS=$'\t' read -r scope name _; do
        [ -n "${scope:-}" ] || continue
        [ -n "${name:-}" ] || continue

        local -a units=()
        mapfile -t units < <(_collect_restart_units "$name" "$scope" | awk 'NF && /\.service$/ && !seen[$0]++')
        if [ "${#units[@]}" -eq 0 ]; then
            mapfile -t units < <(_unit_log_candidates "$name" | awk 'NF && /\.service$/ && !seen[$0]++')
        fi
        if [ "${#units[@]}" -gt 0 ]; then
            _follow_unit_logs "$scope" "$name" "${units[@]}"
            return 0
        fi
    done < <(_resolve_unit_records "$token")

    local -a fallback_units=()
    mapfile -t fallback_units < <(_unit_log_candidates "$token" | awk 'NF && /\.service$/ && !seen[$0]++')
    if [ "${#fallback_units[@]}" -gt 0 ]; then
        _follow_unit_logs user "$token" "${fallback_units[@]}"
        return 0
    fi
    return 1
}
