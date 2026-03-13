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

    # 需求：完全停止，避免自行重新運行（例如：重新登入/重開機後因已啟用而自動拉起）
    # 作法：優先 disable --now（同時停止 + 停用自動啟動）；若不支援則退回 stop。
    local units=()
    if [[ "$token" =~ \.(service|timer|path|socket)$ ]]; then
        units=("$token")
    else
        local base ext
        if [[ "$token" == *.* ]]; then
            base="${token%.*}"
            ext="${token##*.}"
        else
            base="$token"
            ext=""
        fi

        case "$ext" in
            container)
                units=("$token" "$base.service" "container-$base.service")
                ;;
            pod)
                units=("$token" "pod-$base.service" "podman-pod-$base.service")
                ;;
            *)
                mapfile -t units < <(_resolve_unit_candidates "$token")
                ;;
        esac
    fi

    local any=false
    local u
    for u in "${units[@]}"; do
        [ -n "$u" ] || continue
        if _systemctl_user_try disable --now -- "$u"; then
            any=true
        else
            if _systemctl_user_try stop -- "$u"; then
                any=true
            fi
        fi
    done

    if [ "$any" = true ]; then
        echo "✅ 已停止（並停用自動啟動）：$token"
        echo "提示：如要再次啟動，請使用「重新啟動單元」。"
        return 0
    fi

    tgdb_warn "無法停止單元：$token（可能找不到對應 systemd --user 單元）"
    return 1
}

_follow_unit_logs() {
    local unit="$1"
    clear
    echo "=================================="
    echo "❖ 實時查看單元日誌 ❖"
    echo "=================================="
    echo "單元：$unit"
    echo "顯示最近 200 行並持續追蹤。"
    echo "按 Ctrl+C 結束並返回上一層。"
    echo "----------------------------------"
    trap ':' INT
    journalctl --user -u "$unit" -n 200 -f --no-pager 2>/dev/null || true
    trap - INT
}

_unit_try_logs_follow() {
    local token="$1"
    local u
    while IFS= read -r u; do
        if [[ "$u" =~ \.service$ ]]; then
            _follow_unit_logs "$u"
            return 0
        fi
    done < <(_resolve_unit_candidates "$token")
    while IFS= read -r u; do
        _follow_unit_logs "$u"
        return 0
    done < <(_resolve_unit_candidates "$token")
    return 1
}

