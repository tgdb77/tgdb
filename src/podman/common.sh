#!/bin/bash

# Podman：共用工具（rootless/狀態/清理）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_list_user_units() {
    local dir
    dir="$(rm_user_units_dir)"
    [ -d "$dir" ] || return 0
    local exts=("$@")
    if [ ${#exts[@]} -eq 0 ]; then
        exts=(container network volume pod device kube)
    fi
    local find_args=("$dir" -maxdepth 1 \( -type f -o -type l \) \()
    local first=true
    local e
    for e in "${exts[@]}"; do
        if [ "$first" = true ]; then
            find_args+=( -name "*.${e}" )
            first=false
        else
            find_args+=( -o -name "*.${e}" )
        fi
    done
    find_args+=( \) -exec basename {} \; )
    find "${find_args[@]}" 2>/dev/null | sort -u
}

# 建立 rootless 必要目錄並修正擁有權/權限（避免權限錯誤）
_ensure_rootless_env() {
    local user_units_dir
    user_units_dir="$(rm_user_units_dir)"
    local need=("$HOME/.config" "$HOME/.local/share" "$HOME/.cache" "$HOME/.config/containers" "$HOME/.local/share/containers" "$user_units_dir")
    for d in "${need[@]}"; do
        [ -d "$d" ] || mkdir -p "$d"
        if command -v stat >/dev/null 2>&1; then
            local uid
            uid=$(stat -c %u "$d" 2>/dev/null || echo 0)
            if [ "$uid" != "$UID" ]; then
                tgdb_warn "修正目錄擁有權：$d -> $USER:$USER"
                sudo chown -R "$USER:$USER" "$d" 2>/dev/null || true
            fi
        fi
    done
    chmod 700 "$HOME/.config" 2>/dev/null || true
    chmod 700 "$HOME/.config/containers" 2>/dev/null || true
}

check_podman_status() {
    local podman_installed="false"
    local podman_version=""
    if command -v podman >/dev/null 2>&1; then
        podman_installed="true"
        podman_version=$(podman --version 2>/dev/null | awk '{print $3}')
    fi
    printf "%s,%s\n" "$podman_installed" "${podman_version:-unknown}"
}

_print_overview_inline() {
    _ensure_rootless_env
    local status podman_installed podman_version
    status=$(check_podman_status)
    podman_installed=$(echo "$status" | cut -d',' -f1)
    podman_version=$(echo "$status" | cut -d',' -f2)
    echo "[Podman: $([[ "$podman_installed" = true ]] && echo 已安裝 ✅ || echo 未安裝 ❌) ${podman_version:+(v$podman_version)}]"
}

_podman_cleanup_resources() {
    podman container prune -f || true
    podman network prune -f || true
    podman image prune -a -f || true
    podman volume prune -f || true
}

