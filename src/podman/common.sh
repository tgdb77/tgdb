#!/bin/bash

# Podman：共用工具（rootless/狀態/清理）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_podman_scope_normalize() {
    case "$1" in
        user|rootless)
            printf '%s\n' "user"
            ;;
        system|rootful)
            printf '%s\n' "system"
            ;;
        *)
            printf '%s\n' "user"
            ;;
    esac
}

_podman_scope_display_name() {
    case "$1" in
        system) printf '%s\n' "rootful" ;;
        *) printf '%s\n' "rootless" ;;
    esac
}

_podman_unit_dir() {
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    case "$scope" in
        system)
            printf '%s\n' "/etc/containers/systemd"
            ;;
        *)
            rm_user_units_dir
            ;;
    esac
}

_podman_unit_path() {
    local scope="$1" filename="$2"
    printf '%s\n' "$(_podman_unit_dir "$scope")/$filename"
}

_podman_unit_scope_from_path() {
    case "$1" in
        /etc/containers/systemd/*)
            printf '%s\n' "system"
            ;;
        *)
            printf '%s\n' "user"
            ;;
    esac
}

_podman_runtime_dir_for_scope() {
    local scope
    local runtime_dir=""
    scope="$(_podman_scope_normalize "${1:-user}")"
    case "$scope" in
        system)
            if declare -F rm_runtime_app_dir_by_mode >/dev/null 2>&1; then
                runtime_dir="$(rm_runtime_app_dir_by_mode rootful 2>/dev/null || true)"
            fi
            if [ -n "$runtime_dir" ]; then
                printf '%s\n' "$runtime_dir"
            else
                printf '%s\n' "/var/lib/tgdb/app"
            fi
            ;;
        *)
            if declare -F rm_runtime_app_dir_by_mode >/dev/null 2>&1; then
                runtime_dir="$(rm_runtime_app_dir_by_mode rootless 2>/dev/null || true)"
            fi
            if [ -n "$runtime_dir" ]; then
                printf '%s\n' "$runtime_dir"
            elif [ -n "${TGDB_DIR:-}" ]; then
                printf '%s\n' "$TGDB_DIR"
            else
                printf '%s\n' "${PERSIST_CONFIG_DIR:-$HOME/.tgdb}/app"
            fi
            ;;
    esac
}

_podman_token_scope() {
    local token="${1:-}"
    case "$token" in
        user::*)
            printf '%s\n' "user"
            ;;
        system::*)
            printf '%s\n' "system"
            ;;
        *)
            printf '%s\n' ""
            ;;
    esac
}

_podman_token_name() {
    local token="${1:-}"
    case "$token" in
        user::*)
            printf '%s\n' "${token#user::}"
            ;;
        system::*)
            printf '%s\n' "${token#system::}"
            ;;
        *)
            printf '%s\n' "$token"
            ;;
    esac
}

_podman_token_from_record() {
    local scope="$1" name="$2"
    printf '%s\n' "$(_podman_scope_normalize "$scope")::$name"
}

_podman_record_label() {
    local scope="$1" name="$2"
    printf '%s [%s]\n' "$name" "$(_podman_scope_display_name "$scope")"
}

_podman_is_root() {
    [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] 2>/dev/null
}

_podman_run_scope_cmd() {
    local scope="$1"
    shift

    if [ "$(_podman_scope_normalize "$scope")" = "system" ] && ! _podman_is_root; then
        if command -v sudo >/dev/null 2>&1; then
            sudo "$@"
            return $?
        fi
        tgdb_fail "缺少 sudo，無法執行 system scope 指令：$*" 1 || return $?
        return 1
    fi

    "$@"
}

_podman_systemctl() {
    local scope="$1"
    shift

    if [ "$(_podman_scope_normalize "$scope")" = "user" ]; then
        _systemctl_user_try "$@"
        return $?
    fi

    _podman_run_scope_cmd "$scope" systemctl "$@"
}

_podman_split_unit_token() {
    local token="$1"
    # shellcheck disable=SC2178,SC2034 # 透過 nameref 回傳
    local -n out_name_ref="$2"
    # shellcheck disable=SC2178,SC2034 # 透過 nameref 回傳
    local -n out_ext_ref="$3"
    local split_name="$token" split_ext=""

    case "$token" in
        *.container) split_name="${token%.container}"; split_ext="container" ;;
        *.network) split_name="${token%.network}"; split_ext="network" ;;
        *.volume) split_name="${token%.volume}"; split_ext="volume" ;;
        *.kube) split_name="${token%.kube}"; split_ext="kube" ;;
        *.pod) split_name="${token%.pod}"; split_ext="pod" ;;
        *.device) split_name="${token%.device}"; split_ext="device" ;;
        *.image) split_name="${token%.image}"; split_ext="image" ;;
        *.service) split_name="${token%.service}"; split_ext="service" ;;
        *.timer) split_name="${token%.timer}"; split_ext="timer" ;;
        *.path) split_name="${token%.path}"; split_ext="path" ;;
        *.socket) split_name="${token%.socket}"; split_ext="socket" ;;
    esac

    # shellcheck disable=SC2034 # 透過 nameref 回傳
    out_name_ref="$split_name"
    # shellcheck disable=SC2034 # 透過 nameref 回傳
    out_ext_ref="$split_ext"
}

_podman_action_unit_candidates() {
    local token="$1"
    local name ext

    _podman_split_unit_token "$token" name ext

    case "$ext" in
        service|timer|path|socket)
            printf '%s\n' "$token"
            ;;
        container)
            printf '%s\n' "container-$name.service"
            printf '%s\n' "podman-$name.service"
            printf '%s\n' "$name.service"
            ;;
        pod)
            printf '%s\n' "$name-pod.service"
            printf '%s\n' "pod-$name.service"
            printf '%s\n' "podman-pod-$name.service"
            printf '%s\n' "podman-$name-pod.service"
            ;;
        network)
            printf '%s\n' "network-$name.service"
            printf '%s\n' "$name-network.service"
            printf '%s\n' "podman-network-$name.service"
            printf '%s\n' "podman-$name-network.service"
            ;;
        volume)
            printf '%s\n' "volume-$name.service"
            printf '%s\n' "$name-volume.service"
            printf '%s\n' "podman-volume-$name.service"
            printf '%s\n' "podman-$name-volume.service"
            ;;
        kube)
            printf '%s\n' "kube-$name.service"
            printf '%s\n' "$name-kube.service"
            printf '%s\n' "podman-kube-$name.service"
            printf '%s\n' "podman-$name-kube.service"
            ;;
        image)
            printf '%s\n' "image-$name.service"
            printf '%s\n' "$name-image.service"
            printf '%s\n' "podman-image-$name.service"
            printf '%s\n' "podman-$name-image.service"
            ;;
        device)
            printf '%s\n' "device-$name.service"
            printf '%s\n' "$name-device.service"
            printf '%s\n' "podman-device-$name.service"
            printf '%s\n' "podman-$name-device.service"
            ;;
        *)
            local u
            while IFS= read -r u; do
                case "$u" in
                    *.service|*.timer|*.path|*.socket)
                        printf '%s\n' "$u"
                        ;;
                esac
            done < <(_resolve_unit_candidates "$token")
            ;;
    esac | awk 'NF && !seen[$0]++'
}

_podman_existing_action_units() {
    local scope="$1" token="$2"
    local u

    while IFS= read -r u; do
        [ -n "$u" ] || continue
        if _podman_systemctl "$scope" cat -- "$u" >/dev/null 2>&1; then
            printf '%s\n' "$u"
        fi
    done < <(_podman_action_unit_candidates "$token")
}

_podman_systemctl_try_candidates() {
    local scope="$1"
    shift || true

    local -a args=()
    local -a units=()
    local parsing_units=0

    while [ "$#" -gt 0 ]; do
        if [ "$1" = "--" ] && [ "$parsing_units" -eq 0 ]; then
            parsing_units=1
            shift
            continue
        fi
        if [ "$parsing_units" -eq 0 ]; then
            args+=("$1")
        else
            units+=("$1")
        fi
        shift
    done

    if [ "${#units[@]}" -eq 0 ]; then
        _podman_systemctl "$scope" "${args[@]}"
        return $?
    fi

    local unit
    for unit in "${units[@]}"; do
        [ -n "$unit" ] || continue
        if _podman_systemctl "$scope" "${args[@]}" "$unit"; then
            return 0
        fi
    done
    return 1
}

_podman_journalctl() {
    local scope="$1"
    shift

    if [ "$(_podman_scope_normalize "$scope")" = "user" ]; then
        journalctl --user "$@"
        return $?
    fi

    _podman_run_scope_cmd "$scope" journalctl "$@"
}

_podman_podman_cmd() {
    local scope="$1"
    shift

    if [ "$(_podman_scope_normalize "$scope")" = "user" ]; then
        podman "$@"
        return $?
    fi

    _podman_run_scope_cmd "$scope" podman "$@"
}

_podman_collect_unit_records() {
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    shift || true

    local dir
    dir="$(_podman_unit_dir "$scope")"
    [ -d "$dir" ] || return 0

    local exts=("$@")
    if [ ${#exts[@]} -eq 0 ]; then
        exts=(container network volume pod device kube image)
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
    find_args+=( \) -printf '%f\t%p\n' )

    if [ "$scope" = "system" ] && ! _podman_is_root; then
        _podman_run_scope_cmd "$scope" find "${find_args[@]}" 2>/dev/null \
          | awk -v scope="$scope" -F'\t' 'NF>=2 {print scope "\t" $1 "\t" $2}' \
          | sort -t$'\t' -k2,2 -k1,1
        return 0
    fi

    find "${find_args[@]}" 2>/dev/null \
      | awk -v scope="$scope" -F'\t' 'NF>=2 {print scope "\t" $1 "\t" $2}' \
      | sort -t$'\t' -k2,2 -k1,1
}

_podman_resolve_unit_records() {
    local token="$1"
    local scope_hint bare pod_base candidate_base
    local base_name base_ext
    scope_hint="$(_podman_token_scope "$token")"
    bare="$(_podman_token_name "$token")"
    bare="${bare%%$'\n'*}"

    _podman_split_unit_token "$bare" base_name base_ext
    : "${base_ext:=}"

    candidate_base="$base_name"
    if declare -F _pod_base_from_token >/dev/null 2>&1; then
        pod_base="$(_pod_base_from_token "$token" 2>/dev/null || true)"
        if [ -n "$pod_base" ]; then
            candidate_base="$pod_base"
        fi
    fi

    local -a candidates=()
    # 若 token 本身帶有副檔名：
    # - Quadlet 類型（*.container/*.pod/...）→ 只解析「精準檔名」，避免同名 pod/container 被同時匹配。
    # - systemd 類型（*.service/*.timer/...）→ 仍需展開候選，才能回推對應的 Quadlet 檔案。
    if [ -n "$base_ext" ]; then
        case "$base_ext" in
            container|network|volume|pod|kube|device|image)
                candidates=("$bare")
                ;;
            *)
                mapfile -t candidates < <(
                    {
                        _resolve_unit_candidates "$bare" 2>/dev/null || true
                        # Pod 特例：pod-foo.service 這類 token 也優先對應到 foo.pod
                        if [ -n "${pod_base:-}" ]; then
                            _resolve_unit_candidates "${pod_base}.pod" 2>/dev/null || true
                        fi
                        _resolve_unit_candidates "$candidate_base" 2>/dev/null || true
                    } | awk '!seen[$0]++'
                )
                ;;
        esac
    else
        mapfile -t candidates < <(_resolve_unit_candidates "$candidate_base" 2>/dev/null || true)
    fi

    local -A seen=()
    local scope candidate dir path record
    for scope in user system; do
        if [ -n "$scope_hint" ] && [ "$scope" != "$scope_hint" ]; then
            continue
        fi
        dir="$(_podman_unit_dir "$scope")"
        [ -d "$dir" ] || continue
        for candidate in "${candidates[@]}"; do
            [ -n "$candidate" ] || continue
            path="$dir/$candidate"
            if [ -f "$path" ] || [ -L "$path" ]; then
                record="$scope"$'\t'"$candidate"$'\t'"$path"
                if [ -z "${seen[$record]+x}" ]; then
                    seen["$record"]=1
                    printf '%s\n' "$record"
                fi
            fi
        done
    done
}

_podman_user_units_dir() {
    rm_user_units_dir
}

_list_user_units() {
    local dir
    dir="$(_podman_user_units_dir)"
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

_list_podman_units() {
    local exts=("$@")
    {
        _podman_collect_unit_records user "${exts[@]}"
        _podman_collect_unit_records system "${exts[@]}"
    } | awk -F'\t' 'NF>=3 {print $2}' | awk 'NF && !seen[$0]++'
}

# 建立 rootless 必要目錄並修正擁有權/權限（避免權限錯誤）
_ensure_rootless_env() {
    local user_units_dir
    user_units_dir="$(_podman_user_units_dir)"
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
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    _podman_podman_cmd "$scope" container prune -f || true
    _podman_podman_cmd "$scope" network prune -f || true
    _podman_podman_cmd "$scope" image prune -a -f || true
    _podman_podman_cmd "$scope" volume prune -f || true
}

_podman_collect_container_records() {
    local mode="${1:-all}"
    local scope_filter="${2:-user}"
    local -a ps_args=()
    if [ "$mode" = "all" ]; then
        ps_args=(-a)
    fi

    local -a scopes=()
    case "${scope_filter,,}" in
        all|both)
            scopes=(user system)
            ;;
        system|rootful)
            scopes=(system)
            ;;
        user|rootless|""|*)
            # 預設僅列 rootless，避免在一般情境下觸發 sudo 密碼提示。
            scopes=(user)
            ;;
    esac

    local scope row
    for scope in "${scopes[@]}"; do
        if [ "$scope" = "system" ] && ! _podman_is_root && ! command -v sudo >/dev/null 2>&1; then
            continue
        fi
        while IFS= read -r row; do
            [ -n "$row" ] || continue
            printf '%s\t%s\n' "$scope" "$row"
        done < <(_podman_podman_cmd "$scope" ps "${ps_args[@]}" --format "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || true)
    done
}

_podman_print_scope_ps_table() {
    local scope="$1" mode="${2:-all}"
    local -a ps_args=()
    local label
    label="$(_podman_scope_display_name "$scope")"

    if [ "$mode" = "all" ]; then
        ps_args=(-a)
    fi

    echo "--- ${label} 容器 ---"
    if [ "$scope" = "system" ] && ! _podman_is_root && ! command -v sudo >/dev/null 2>&1; then
        tgdb_warn "找不到 sudo，無法顯示 rootful 容器清單。"
        return 1
    fi

    if ! _podman_podman_cmd "$scope" ps "${ps_args[@]}" 2>/dev/null; then
        tgdb_warn "無法顯示 ${label} 容器清單。"
        return 1
    fi
    return 0
}

_podman_print_container_overview() {
    local mode="${1:-all}"
    local scope_filter="${2:-user}"
    local printed_any=0

    local -a scopes=()
    case "${scope_filter,,}" in
        all|both)
            scopes=(user system)
            ;;
        system|rootful)
            scopes=(system)
            ;;
        user|rootless|*)
            scopes=(user)
            ;;
    esac

    local scope
    for scope in "${scopes[@]}"; do
        if [ "$printed_any" -eq 1 ]; then
            echo
        fi
        if _podman_print_scope_ps_table "$scope" "$mode"; then
            printed_any=1
        fi
    done

    if [ "$printed_any" -eq 0 ]; then
        echo "目前沒有可顯示的容器。"
    fi
}
