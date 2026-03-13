#!/bin/bash

# Podman：Quadlet 單元操作（解析候選單元/啟用/停用/重啟）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_resolve_unit_candidates() {
    local token="$1"
    local name ext candidates=()

    if [[ "$token" =~ \.(service|timer|path|socket)$ ]]; then
        candidates+=("$token")
    fi

    if [[ "$token" == *.* ]]; then
        name="${token%.*}"
        ext="${token##*.}"
    else
        name="$token"
        ext=""
    fi

    if [ -n "$ext" ]; then
        candidates+=("$name.$ext")
    fi

    candidates+=(
        "$name.service"
        "container-$name.service"
        "podman-$name.service"
        "podman-network-$name.service"
        "network-$name.service"
        "$name-network.service"
        "podman-$name-network.service"
        "podman-volume-$name.service"
        "volume-$name.service"
        "$name-volume.service"
        "podman-$name-volume.service"
        "podman-kube-$name.service"
        "kube-$name.service"
        "$name-kube.service"
        "podman-$name-kube.service"
        "podman-pod-$name.service"
        "pod-$name.service"
        "$name-pod.service"
        "podman-$name-pod.service"
        "podman-image-$name.service"
        "image-$name.service"
        "$name-image.service"
        "podman-$name-image.service"
        "podman-device-$name.service"
        "device-$name.service"
        "$name-device.service"
        "podman-$name-device.service"
    )

    if [ -z "$ext" ]; then
        candidates+=(
            "$name.container" "$name.network" "$name.volume" "$name.kube" "$name.pod"
        )
    fi

    awk '!seen[$0]++' < <(printf "%s\n" "${candidates[@]}")
}

_unit_try_enable_now() {
    local token="$1"
    local units=()
    mapfile -t units < <(_resolve_unit_candidates "$token")

    # 先嘗試啟用（只建立自動啟動連結，不等待啟動完成）
    _systemctl_user_try enable -- "${units[@]}" || true

    # 再送出啟動（不等待 jobs 完成），避免 systemctl 阻塞導致選單卡住 1–2 分鐘
    _systemctl_user_try start --no-block -- "${units[@]}" && return 0
    return 1
}

_unit_try_disable_now() {
    local token="$1"
    local u
    while IFS= read -r u; do
        _systemctl_user_try disable --now -- "$u" || true
    done < <(_resolve_unit_candidates "$token")
}

_collect_restart_units() {
    local token="$1"
    local pod_base=""

    if declare -F _pod_base_from_token >/dev/null 2>&1; then
        pod_base="$(_pod_base_from_token "$token" 2>/dev/null || true)"
    fi

    # Pod 單元重啟時，同步納入成員容器，避免僅重啟 pod service 本身。
    if [ -n "$pod_base" ] && declare -F _list_pod_member_container_unit_files >/dev/null 2>&1; then
        local -a members=()
        local u m

        while IFS= read -r u; do
            [ -n "$u" ] && printf '%s\n' "$u"
        done < <(_resolve_unit_candidates "${pod_base}.pod")

        mapfile -t members < <(_list_pod_member_container_unit_files "$pod_base")
        for m in "${members[@]}"; do
            while IFS= read -r u; do
                [ -n "$u" ] && printf '%s\n' "$u"
            done < <(_resolve_unit_candidates "$m")
        done
        return 0
    fi

    _resolve_unit_candidates "$token"
}

_unit_try_restart() {
    local token="$1"
    local units=()
    mapfile -t units < <(_collect_restart_units "$token" | awk 'NF && !seen[$0]++')

    # 先重載，避免剛新增/修改 Quadlet 檔案但尚未載入導致找不到單元。
    _systemctl_user_try daemon-reload || true

    local u
    local any_start=false

    # 先停再啟，避免 restart 只命中部分候選單元時造成 pod 成員狀態不一致。
    for u in "${units[@]}"; do
        [ -n "$u" ] || continue
        _systemctl_user_try stop -- "$u" || true
    done

    for u in "${units[@]}"; do
        [ -n "$u" ] || continue
        if _systemctl_user_try start --no-block -- "$u"; then
            any_start=true
        fi
    done

    if [ "$any_start" = true ]; then
        return 0
    fi
    return 1
}
