#!/bin/bash

# Podman：安裝/更新與系統設定（sysctl、預設網路、polkit）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_podman_polkit_marker_path() {
    local base
    base="$(rm_persist_config_dir 2>/dev/null || true)"
    [ -n "$base" ] || { echo ""; return 0; }
    printf '%s\n' "$base/podman/polkit_installed_by_tgdb"
}

_podman_mark_polkit_installed() {
    local pkg="$1"
    [ -n "$pkg" ] || return 0
    local marker
    marker="$(_podman_polkit_marker_path)"
    [ -n "$marker" ] || return 0
    mkdir -p "$(dirname "$marker")" 2>/dev/null || true
    printf '%s\n' "$pkg" >"$marker" 2>/dev/null || true
}

_podman_try_install_pkttyagent() {
    command -v pkttyagent >/dev/null 2>&1 && return 0
    [ -x /usr/bin/pkttyagent ] && return 0

    if pkg_install_role "polkit-agent"; then
        if command -v pkttyagent >/dev/null 2>&1 || [ -x /usr/bin/pkttyagent ]; then
            _podman_mark_polkit_installed "${TGDB_PKG_LAST_SELECTED:-}"
            return 0
        fi
    fi
    return 1
}

_apply_sysctl_unprivileged_ports() {
    local sysctl_dir="/etc/sysctl.d"
    local sysctl_file="$sysctl_dir/99-tgdb-podman-rootless-ports.conf"

    if ! _tgdb_run_privileged mkdir -p "$sysctl_dir"; then
        tgdb_err "無法建立 $sysctl_dir，略過特權埠設定。"
        return 1
    fi

    if ! _tgdb_run_privileged tee "$sysctl_file" >/dev/null <<'EOF'
# TGDB: podman rootless privileged-ports
# 為何：允許非 root 使用者綁定特權埠；
net.ipv4.ip_unprivileged_port_start=25
EOF
    then
        tgdb_err "無法寫入 $sysctl_file，略過特權埠設定。"
        return 1
    fi

    # 優先用 --system 模擬開機行為；若不支援再退回單檔載入。
    if ! _tgdb_run_privileged sysctl --system >/dev/null 2>&1; then
        if ! _tgdb_run_privileged sysctl -p "$sysctl_file" >/dev/null 2>&1; then
            tgdb_warn "已寫入 $sysctl_file，但目前無法立即套用，請稍後手動執行 sysctl --system。"
        fi
    fi
}

_revert_sysctl_unprivileged_ports() {
    local sysctl_file="/etc/sysctl.d/99-tgdb-podman-rootless-ports.conf"

    if [ -f "$sysctl_file" ]; then
        _tgdb_run_privileged rm -f "$sysctl_file" || true
    fi
    if ! _tgdb_run_privileged sysctl --system >/dev/null 2>&1; then
        _tgdb_run_privileged sysctl -w net.ipv4.ip_unprivileged_port_start=1024 >/dev/null 2>&1 || true
        _tgdb_run_privileged sysctl -p >/dev/null 2>&1 || true
    fi
}

_install_default_tgdb_network_quadlet() {
    # 安裝預設網路單元：讓未來 app 可直接使用 tgdb 網路（並在安裝時嘗試直接建立）。
    local src dest_dir dest
    src="$CONFIG_DIR/quadlet/networks/tgdb.network"
    dest_dir="$(rm_service_runtime_quadlet_dir_by_mode "tgdb" rootless 2>/dev/null || printf '%s\n' "$(rm_user_units_dir)/tgdb")"
    dest="$dest_dir/tgdb.network"

    if [ ! -f "$src" ]; then
        tgdb_warn "找不到預設網路單元檔，略過：$src"
        return 0
    fi

    mkdir -p "$dest_dir" 2>/dev/null || true

    if [ -f "$dest" ]; then
        echo "ℹ️ 預設網路單元已存在，略過覆蓋：$dest"
    else
        if cp "$src" "$dest" 2>/dev/null; then
            chmod 644 "$dest" 2>/dev/null || true
            if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null; then
                chown "$(_detect_invoking_uid)":"$(_detect_invoking_gid)" "$dest" 2>/dev/null || true
            fi
            echo "✅ 已安裝預設網路單元：$dest"
        else
            tgdb_warn "無法安裝預設網路單元到：$dest（請確認權限）"
        fi
    fi

    # 複製完成後直接嘗試建立 tgdb 網路（若已存在則略過）。
    if command -v podman >/dev/null 2>&1; then
        if podman network inspect tgdb >/dev/null 2>&1; then
            return 0
        fi
    fi

    if command -v systemctl >/dev/null 2>&1; then
        _systemctl_user_try daemon-reload || true
        _systemctl_user_try enable --now -- "tgdb.network" "podman-network-tgdb.service" || true
        _systemctl_user_try start -- "tgdb.network" "podman-network-tgdb.service" || true
    fi

    if command -v podman >/dev/null 2>&1; then
        if podman network inspect tgdb >/dev/null 2>&1; then
            echo "✅ 已建立預設 Podman 網路：tgdb"
            return 0
        fi
        if podman network create tgdb >/dev/null 2>&1; then
            echo "✅ 已建立預設 Podman 網路：tgdb（未透過 systemd/Quadlet）"
        else
            tgdb_warn "無法自動建立預設 Podman 網路：tgdb（請稍後手動執行 systemctl --user enable --now tgdb.network 或 podman network create tgdb）"
        fi
    else
        tgdb_warn "Podman 未安裝，無法自動建立預設網路：tgdb"
    fi
    return 0
}

_enable_user_systemd_and_linger() {
    echo "❖ 啟用使用者 systemd 與 linger ❖"
    if command -v loginctl >/dev/null 2>&1; then
        if command -v sudo >/dev/null 2>&1; then
            sudo loginctl enable-linger "$USER" >/dev/null 2>&1 || true
        else
            loginctl enable-linger "$USER" >/dev/null 2>&1 || true
        fi
    fi
    _systemctl_user_try daemon-reload || true
    echo "✅ 已嘗試啟用使用者 systemd/linger（若環境不支援可忽略訊息）"
}

_install_podman() {
    echo "❖ 安裝/更新 Podman（啟用 sysctl 特權埠）❖"
    install_package "podman" || true
    _podman_try_install_pkttyagent || true
    echo "✅ 完成套件安裝/更新"
    _ensure_rootless_env
    _enable_user_systemd_and_linger
    _install_default_tgdb_network_quadlet
    _ensure_containers_configs
    _apply_sysctl_unprivileged_ports
    tgdb_warn "注意：已將 net.ipv4.ip_unprivileged_port_start 調整為 25，允許非 root 綁定 25–65535 埠。"
    tgdb_warn "建議僅在『單一使用者』的 VPS 環境使用；如有多個系統帳號，請評估風險或考慮恢復預設值。"
}
