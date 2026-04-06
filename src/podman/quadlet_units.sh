#!/bin/bash

# Podman：Quadlet 單元操作（解析候選單元/啟用/停用/重啟）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_resolve_unit_candidates() {
    local token="$1"
    local name ext candidates=()

    if [[ "$token" =~ \.(service|timer|path|socket)$ ]]; then
        candidates+=("$token")
    fi

    _podman_split_unit_token "$token" name ext

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

_resolve_unit_records() {
    _podman_resolve_unit_records "$1"
}

_unit_try_enable_now() {
    local token="$1"
    local scope name
    local -a units=()

    while IFS=$'\t' read -r scope name _; do
        [ -n "${scope:-}" ] || continue
        [ -n "${name:-}" ] || continue
        _podman_systemctl "$scope" daemon-reload >/dev/null 2>&1 || true
        # 啟用/啟動只應針對「該單元類型」的 systemd unit，避免同名 pod/container 時誤啟動 pod。
        mapfile -t units < <(_podman_action_unit_candidates "$name" | awk 'NF && !seen[$0]++')
        [ "${#units[@]}" -gt 0 ] || continue

        _podman_systemctl_try_candidates "$scope" enable -- "${units[@]}" >/dev/null 2>&1 || true
        if _podman_systemctl_try_candidates "$scope" start --no-block -- "${units[@]}" >/dev/null 2>&1; then
            return 0
        fi
    done < <(_resolve_unit_records "$token")

    return 1
}

_unit_try_disable_now() {
    local token="$1"
    local scope name u
    while IFS=$'\t' read -r scope name _; do
        [ -n "${scope:-}" ] || continue
        [ -n "${name:-}" ] || continue
        while IFS= read -r u; do
            _podman_systemctl "$scope" disable --now -- "$u" >/dev/null 2>&1 || true
        done < <(_resolve_unit_candidates "$name" | awk 'NF && !seen[$0]++')
    done < <(_resolve_unit_records "$token")
}

_collect_restart_units() {
    local token="$1"
    local scope_hint="${2:-}"
    local pod_base=""
    local scope=""

    if declare -F _pod_base_from_token >/dev/null 2>&1; then
        pod_base="$(_pod_base_from_token "$token" 2>/dev/null || true)"
    fi
    if [ -n "$scope_hint" ]; then
        scope="$scope_hint"
    elif declare -F _podman_token_scope >/dev/null 2>&1; then
        scope="$(_podman_token_scope "$token" 2>/dev/null || true)"
    fi

    # Pod 單元重啟時，同步納入成員容器，避免僅重啟 pod service 本身。
    if [ -n "$pod_base" ] && declare -F _list_pod_member_container_unit_files >/dev/null 2>&1; then
        local -a members=()
        local u m

        while IFS= read -r u; do
            [ -n "$u" ] && printf '%s\n' "$u"
        done < <(
            if declare -F _podman_action_unit_candidates >/dev/null 2>&1; then
                _podman_action_unit_candidates "${pod_base}.pod"
            else
                _resolve_unit_candidates "${pod_base}.pod"
            fi
        )

        mapfile -t members < <(_list_pod_member_container_unit_files_by_scope "${scope:-user}" "$pod_base")
        for m in "${members[@]}"; do
            while IFS= read -r u; do
                [ -n "$u" ] && printf '%s\n' "$u"
            done < <(
                if declare -F _podman_action_unit_candidates >/dev/null 2>&1; then
                    _podman_action_unit_candidates "$m"
                else
                    _resolve_unit_candidates "$m"
                fi
            )
        done
        return 0
    fi

    # 非 Pod：優先用「依單元類型收斂」的候選清單，避免誤把同名 pod 一起重啟。
    # 典型案例：pod= grafana.pod，且同時存在 grafana.container（成員容器），
    # 若用 _resolve_unit_candidates 會把 pod-grafana.service 也納入，導致重啟容器時整個 pod 被重啟。
    if declare -F _podman_action_unit_candidates >/dev/null 2>&1; then
        _podman_action_unit_candidates "$token"
        return 0
    fi

    _resolve_unit_candidates "$token"
}

_unit_try_restart() {
    local token="$1"
    local any_start=false
    local scope name

    while IFS=$'\t' read -r scope name _; do
        [ -n "${scope:-}" ] || continue
        [ -n "${name:-}" ] || continue

        local -a units=()
        _podman_systemctl "$scope" daemon-reload >/dev/null 2>&1 || true
        mapfile -t units < <(_collect_restart_units "$name" "$scope" | awk 'NF && !seen[$0]++')
        [ "${#units[@]}" -gt 0 ] || continue

        local pod_base=""
        if declare -F _pod_base_from_token >/dev/null 2>&1; then
            pod_base="$(_pod_base_from_token "$name" 2>/dev/null || true)"
        fi

        # 非 Pod：只挑「第一個存在的候選 unit」做 restart，避免同名 alias 造成誤重啟整個 pod。
        if [ -z "$pod_base" ]; then
            if _podman_systemctl_try_candidates "$scope" restart --no-block -- "${units[@]}" >/dev/null 2>&1; then
                any_start=true
            fi
            continue
        fi

        # Pod：維持既有行為（pod + 成員容器一起重啟）
        local u
        for u in "${units[@]}"; do
            [ -n "$u" ] || continue
            _podman_systemctl "$scope" stop -- "$u" >/dev/null 2>&1 || true
        done

        for u in "${units[@]}"; do
            [ -n "$u" ] || continue
            if _podman_systemctl "$scope" start --no-block -- "$u" >/dev/null 2>&1; then
                any_start=true
            fi
        done
    done < <(_resolve_unit_records "$token")

    [ "$any_start" = true ]
}
