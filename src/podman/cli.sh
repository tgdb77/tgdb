#!/bin/bash

# Podman：CLI 介面（供 tgdb.sh CLI 路由呼叫）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

podman_install_cli() {
    echo "⚙️ (CLI) 安裝/更新 Podman"
    _install_podman
}

# 將 CLI 參數展開為目標清單（支援多參數與逗號分隔）。
_podman_cli_expand_targets() {
    local raw
    local -a parts=()
    local part

    for raw in "$@"; do
        [ -n "$raw" ] || continue
        raw="${raw//,/ }"
        read -r -a parts <<< "$raw"
        for part in "${parts[@]}"; do
            [ -n "$part" ] && printf '%s\n' "$part"
        done
    done
}

_podman_cli_list_stop_unit_targets() {
    _list_podman_units container pod
}

_podman_cli_list_restart_unit_targets() {
    _list_podman_units container pod network volume image device
}

_podman_cli_list_remove_unit_targets() {
    _list_podman_units container network volume pod device kube
}

_podman_cli_collect_unit_targets() {
    local usage_single="$1" usage_all="$2" list_fn="$3" action_label="$4"
    shift 4

    local -a inputs=()
    mapfile -t inputs < <(_podman_cli_expand_targets "$@")
    if [ "${#inputs[@]}" -eq 0 ]; then
        local msg
        printf -v msg '%s\n%s' \
          "用法：$usage_single" \
          "   或：$usage_all"
        tgdb_fail "$msg" 2 || return $?
    fi

    local token lower
    local select_all=false
    for token in "${inputs[@]}"; do
        lower="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
        case "$lower" in
            a)
                select_all=true
                break
                ;;
        esac
    done

    local -a targets=()
    if [ "$select_all" = true ]; then
        local confirm=""
        for token in "${inputs[@]}"; do
            lower="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
            case "$lower" in
                a) ;;
                0|1)
                    if [ -z "$confirm" ]; then
                        confirm="$lower"
                    else
                        local msg_dup
                        printf -v msg_dup '%s\n%s' \
                          "用法：$usage_single" \
                          "   或：$usage_all"
                        tgdb_fail "$msg_dup" 2 || return $?
                    fi
                    ;;
                *)
                    local msg_invalid
                    printf -v msg_invalid '%s\n%s' \
                      "用法：$usage_single" \
                      "   或：$usage_all"
                    tgdb_fail "$msg_invalid" 2 || return $?
                    ;;
            esac
        done

        if [ -z "$confirm" ]; then
            local msg_need_confirm
            printf -v msg_need_confirm '%s\n%s' \
              "使用 a（全部）時，需額外確認參數。" \
              "用法：$usage_all（0=執行、1=取消）"
            tgdb_fail "$msg_need_confirm" 2 || return $?
        fi

        local confirm_rc=0
        _podman_cli_confirm_flag_01 "$confirm" "$usage_all" || confirm_rc=$?
        case "$confirm_rc" in
            0) ;;
            10)
                echo "ℹ️ 已取消全部${action_label}（確認參數=1）" >&2
                return 10
                ;;
            *) return "$confirm_rc" ;;
        esac

        mapfile -t targets < <("$list_fn")
        if [ "${#targets[@]}" -eq 0 ]; then
            echo "ℹ️ 目前沒有可操作的單元" >&2
            return 10
        fi
    else
        targets=("${inputs[@]}")
    fi

    printf '%s\n' "${targets[@]}" | awk 'NF && !seen[$0]++'
}

_podman_cli_batch_unit_action() {
    local action_label="$1" action_fn="$2" usage_single="$3" usage_all="$4" list_fn="$5"
    shift 5

    local collect_rc=0
    local collected=""
    local -a targets=()
    collected="$(_podman_cli_collect_unit_targets "$usage_single" "$usage_all" "$list_fn" "$action_label" "$@")" || collect_rc=$?
    case "$collect_rc" in
        0) ;;
        10) return 0 ;;
        *) return "$collect_rc" ;;
    esac

    if [ -n "$collected" ]; then
        mapfile -t targets <<< "$collected"
    fi
    if [ "${#targets[@]}" -eq 0 ]; then
        tgdb_warn "未提供任何可${action_label}的單元"
        return 1
    fi

    local ok=0 fail=0
    local target
    for target in "${targets[@]}"; do
        if "$action_fn" "$target"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
        fi
    done

    echo "${action_label}結果：成功=$ok / 失敗=$fail"
    [ "$fail" -eq 0 ]
}

_podman_cli_stop_unit_target() { _unit_try_stop "$1"; }
_podman_cli_restart_unit_target() { _unit_try_restart "$1"; }
_podman_cli_remove_unit_target() { _remove_quadlet_unit "$1"; }

_podman_cli_batch_remove_targets() {
    local label="$1" remove_fn="$2"
    shift 2
    local -a targets=("$@")
    local ok=0 fail=0
    local target

    for target in "${targets[@]}"; do
        if "$remove_fn" "$target"; then
            echo "✅ 已移除${label}：$target"
            ok=$((ok + 1))
        else
            tgdb_warn "移除${label}失敗：$target"
            fail=$((fail + 1))
        fi
    done

    echo "結果：成功=$ok / 失敗=$fail"
    [ "$fail" -eq 0 ]
}

_podman_cli_remove_image_target() { podman rmi -f "$1"; }
_podman_cli_remove_network_target() { podman network rm "$1"; }
_podman_cli_remove_volume_target() { podman volume rm "$1"; }

_podman_cli_parse_scope_target() {
    local token="$1" out_scope_var="$2" out_target_var="$3"
    local scope="user" target="$token"

    case "$token" in
        user::*)
            scope="user"
            target="${token#user::}"
            ;;
        system::*)
            scope="system"
            target="${token#system::}"
            ;;
    esac

    printf -v "$out_scope_var" '%s' "$scope"
    printf -v "$out_target_var" '%s' "$target"
}

_podman_cli_list_all_image_targets() {
    podman images --format '{{.ID}}' 2>/dev/null | awk 'NF && !seen[$0]++'
}

_podman_cli_list_all_network_targets() {
    podman network ls --format '{{.Name}}' 2>/dev/null | awk 'NF'
}

_podman_cli_list_all_volume_targets() {
    podman volume ls --format '{{.Name}}' 2>/dev/null | awk 'NF'
}

_podman_cli_confirm_flag_01() {
    local confirm="${1:-}" usage="${2:-}"
    case "$confirm" in
        0) return 0 ;;
        1) return 10 ;;
        *)
            local msg
            printf -v msg '%s\n%s' \
              "用法：$usage" \
              "   參數：0=執行（不可逆）、1=取消"
            tgdb_fail "$msg" 2 || return $?
            return 2
            ;;
    esac
}

podman_stop_unit_cli() {
    _podman_cli_batch_unit_action \
      "停止" \
      _podman_cli_stop_unit_target \
      "t 5 5 <unit_file_or_name> [更多 unit_file_or_name ...]" \
      "t 5 5 a <0|1>" \
      _podman_cli_list_stop_unit_targets \
      "$@"
}

podman_restart_unit_cli() {
    _podman_cli_batch_unit_action \
      "重啟" \
      _podman_cli_restart_unit_target \
      "t 5 6 <unit_file_or_name> [更多 unit_file_or_name ...]" \
      "t 5 6 a <0|1>" \
      _podman_cli_list_restart_unit_targets \
      "$@"
}

podman_remove_unit_cli() {
    _podman_cli_batch_unit_action \
      "移除" \
      _podman_cli_remove_unit_target \
      "t 5 7 <unit_file_or_name> [更多 unit_file_or_name ...]" \
      "t 5 7 a <0|1>" \
      _podman_cli_list_remove_unit_targets \
      "$@"
}

podman_pull_image_cli() {
    local img="$1"
    if [ -z "$img" ]; then
        tgdb_fail "映像名稱不得為空" 1 || return $?
    fi
    podman pull "$img"
}

podman_remove_image_cli() {
    local -a imgs=()
    mapfile -t imgs < <(_podman_cli_expand_targets "$@")
    if [ "${#imgs[@]}" -eq 0 ]; then
        tgdb_fail "用法：t 5 9 2 <image_or_id> [更多 image_or_id ...]" 2 || return $?
    fi
    _podman_cli_batch_remove_targets "映像" _podman_cli_remove_image_target "${imgs[@]}"
}

podman_remove_all_images_cli() {
    local confirm="${1:-}"
    local confirm_rc=0
    _podman_cli_confirm_flag_01 "$confirm" "t 5 9 3 <0|1>" || confirm_rc=$?
    case "$confirm_rc" in
        0) ;;
        10)
            echo "ℹ️ 已取消全部移除映像（確認參數=1）"
            return 0
            ;;
        *) return "$confirm_rc" ;;
    esac

    local -a imgs=()
    mapfile -t imgs < <(_podman_cli_list_all_image_targets)
    if [ "${#imgs[@]}" -eq 0 ]; then
        echo "ℹ️ 目前沒有可移除的映像"
        return 0
    fi
    _podman_cli_batch_remove_targets "映像" _podman_cli_remove_image_target "${imgs[@]}"
}

podman_create_network_cli() {
    local net="$1"
    if [ -z "$net" ]; then
        tgdb_fail "網路名稱不得為空" 1 || return $?
    fi
    podman network create "$net"
}

podman_remove_network_cli() {
    local -a nets=()
    mapfile -t nets < <(_podman_cli_expand_targets "$@")
    if [ "${#nets[@]}" -eq 0 ]; then
        tgdb_fail "用法：t 5 10 2 <network_name_or_id> [更多 network_name_or_id ...]" 2 || return $?
    fi
    _podman_cli_batch_remove_targets "網路" _podman_cli_remove_network_target "${nets[@]}"
}

podman_remove_all_networks_cli() {
    local confirm="${1:-}"
    local confirm_rc=0
    _podman_cli_confirm_flag_01 "$confirm" "t 5 10 3 <0|1>" || confirm_rc=$?
    case "$confirm_rc" in
        0) ;;
        10)
            echo "ℹ️ 已取消全部移除網路（確認參數=1）"
            return 0
            ;;
        *) return "$confirm_rc" ;;
    esac

    local -a nets=()
    mapfile -t nets < <(_podman_cli_list_all_network_targets)
    if [ "${#nets[@]}" -eq 0 ]; then
        echo "ℹ️ 目前沒有可移除的網路"
        return 0
    fi
    _podman_cli_batch_remove_targets "網路" _podman_cli_remove_network_target "${nets[@]}"
}

podman_create_volume_cli() {
    local vol="$1"
    if [ -z "$vol" ]; then
        tgdb_fail "卷名稱不得為空" 1 || return $?
    fi
    podman volume create "$vol"
}

podman_remove_volume_cli() {
    local -a vols=()
    mapfile -t vols < <(_podman_cli_expand_targets "$@")
    if [ "${#vols[@]}" -eq 0 ]; then
        tgdb_fail "用法：t 5 11 2 <volume_name_or_id> [更多 volume_name_or_id ...]" 2 || return $?
    fi
    _podman_cli_batch_remove_targets "卷" _podman_cli_remove_volume_target "${vols[@]}"
}

podman_remove_all_volumes_cli() {
    local confirm="${1:-}"
    local confirm_rc=0
    _podman_cli_confirm_flag_01 "$confirm" "t 5 11 3 <0|1>" || confirm_rc=$?
    case "$confirm_rc" in
        0) ;;
        10)
            echo "ℹ️ 已取消全部移除卷（確認參數=1）"
            return 0
            ;;
        *) return "$confirm_rc" ;;
    esac

    local -a vols=()
    mapfile -t vols < <(_podman_cli_list_all_volume_targets)
    if [ "${#vols[@]}" -eq 0 ]; then
        echo "ℹ️ 目前沒有可移除的卷"
        return 0
    fi
    _podman_cli_batch_remove_targets "卷" _podman_cli_remove_volume_target "${vols[@]}"
}

podman_exec_container_cli() {
    local target="$1"
    local scope="user"
    if [ -z "$target" ]; then
        tgdb_fail "容器名稱或 ID 不得為空" 1 || return $?
    fi
    if ! command -v podman >/dev/null 2>&1; then
        tgdb_fail "Podman 未安裝，無法進入容器" 1 || return $?
    fi
    _podman_cli_parse_scope_target "$target" scope target
    echo "⚙️ (CLI) 嘗試進入容器：$target"
    echo "提示：進入容器後輸入 exit 可返回終端。"
    if _podman_podman_cmd "$scope" exec -it "$target" /bin/sh; then
        echo
        echo "✅ 已離開容器：$target"
        return 0
    else
        echo
        tgdb_fail "無法進入容器，請確認容器存在且內部有 /bin/sh" 1 || return $?
    fi
}

podman_cleanup_cli() {
    echo "⚙️ (CLI) 清除孤立容器/網路/映像/卷"
    _podman_cleanup_resources
    echo "✅ 清理完成"
}

podman_uninstall_cli() {
    local confirm="${1:-}"
    if [ "$confirm" != "YES" ]; then
        local msg
        printf -v msg '%s\n%s' \
          "用法：5 d YES" \
          "   說明：此操作不可逆，需輸入大寫 YES 才會執行。"
        tgdb_fail "$msg" 2 || return $?
    fi

    echo "=================================="
    tgdb_warn "(CLI) 完全移除 Podman/Quadlet 環境（不可逆）"
    echo "=================================="
    _run_podman_uninstall_flow
    echo "✅ 已完成移除流程（包含 rootless/rootful 資源，並清理 TGDB 管理的 rootful 單元）。"
}
