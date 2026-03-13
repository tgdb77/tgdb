#!/bin/bash

# Podman：containers 設定（policy.json / registries.conf）
# 說明：互動菜單已集中於 src/podman/menu.sh，此檔案保留底層輔助函式。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_user_containers_dir() { echo "$HOME/.config/containers"; }
_system_containers_dir() { echo "/etc/containers"; }

_user_policy() { echo "$( _user_containers_dir )/policy.json"; }
_user_registries() { echo "$( _user_containers_dir )/registries.conf"; }
_system_policy() { echo "$( _system_containers_dir )/policy.json"; }
_system_registries() { echo "$( _system_containers_dir )/registries.conf"; }

_ensure_containers_common_installed() {
    if ! pkg_install_role "containers-common"; then
        tgdb_warn "無法安裝 containers-common，請手動確認您的發行版套件名稱。"
        return 1
    fi
    return 0
}

_file_exists_any() { [ -f "$1" ] || [ -f "$2" ]; }

_ensure_containers_configs() {
    local need_policy=false need_reg=false
    _file_exists_any "$(_user_policy)" "$(_system_policy)" || need_policy=true
    _file_exists_any "$(_user_registries)" "$(_system_registries)" || need_reg=true
    if [ "$need_policy" = true ] || [ "$need_reg" = true ]; then
        tgdb_warn "偵測到缺少 containers 設定（policy/registries），嘗試安裝 containers-common..."
        _ensure_containers_common_installed || true
    fi
}

_copy_system_to_user_if_missing() {
    _ensure_rootless_env
    mkdir -p "$( _user_containers_dir )"
    if [ ! -f "$( _user_policy )" ] && [ -f "$( _system_policy )" ]; then
        cp "$( _system_policy )" "$( _user_policy )"
        echo "已複製系統 policy.json 到使用者目錄"
    fi
    if [ ! -f "$( _user_registries )" ] && [ -f "$( _system_registries )" ]; then
        cp "$( _system_registries )" "$( _user_registries )"
        echo "已複製系統 registries.conf 到使用者目錄"
    fi
}

_create_safe_defaults_if_missing() {
    _ensure_rootless_env
    mkdir -p "$( _user_containers_dir )"
    if [ ! -f "$( _user_policy )" ] && ! _file_exists_any "$( _user_policy )" "$( _system_policy )"; then
        cat >"$( _user_policy )" <<'EOF'
{
  "default": [ { "type": "reject" } ]
}
EOF
        echo "已建立安全 policy.json（預設拒絕）於使用者目錄"
    fi
    if [ ! -f "$( _user_registries )" ] && ! _file_exists_any "$( _user_registries )" "$( _system_registries )"; then
        cat >"$( _user_registries )" <<'EOF'
unqualified-search-registries = ["docker.io"]
EOF
        echo "已建立預設 registries.conf 於使用者目錄"
    fi
}
