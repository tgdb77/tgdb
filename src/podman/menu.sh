#!/bin/bash

# Podman：主選單
# 說明：為了方便維護與查找，所有互動菜單集中於此檔案（主選單 + 子選單）。
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

podman_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "Podman/Quadlet 管理需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ Podman/Quadlet 管理 ❖"
        echo "=================================="
        _print_overview_inline
        echo "提示：容器清單會分別用 podman ps / sudo podman ps 顯示 rootless 與 rootful。"
        echo "註：映像 / 網路 / 卷等資源子選單目前仍以目前使用者的 Podman 為主。"
        _podman_print_container_overview all
        echo "----------------------------------"
        echo "1. 安裝/更新 Podman "
        echo "2. 新增單元 "
        echo "3. 編輯現有單元 "
        echo "4. 查看單元日誌 "
        echo "5. 停止單元（可多選）"
        echo "6. 重新啟動單元（可多選）"
        echo "7. 移除單元（可多選）"
        echo "8. 進入容器 Shell"
        echo "9. 映像管理"
        echo "10. 網路管理"
        echo "11. 卷管理"
        echo "12. 清理孤立資源"
        echo "13. 容器自動更新（podman auto-update）"
        echo "14. 編輯 containers 設定"
        echo "----------------------------------"
        echo "d. 完全移除 Podman/Quadlet 環境"
        echo "----------------------------------"
        echo "0. 返回主選單"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-14]: " choice
        case "$choice" in
            1) _install_podman ; ui_pause ;;
            2) _create_or_edit_quadlet_unit ; ui_pause ;;
            3) _edit_existing_unit_and_reload_restart || { echo "返回上層"; sleep 1; continue; }; ui_pause ;;
            4) n=$(_pick_existing_unit_file container pod) || { echo "返回上層"; sleep 1; continue; }; _unit_try_logs_follow "$n" ;;
            5)
                local -a stop_units=()
                mapfile -t stop_units < <(_pick_existing_unit_files_multi "停止單元" container pod)
                if [ "${#stop_units[@]}" -eq 0 ]; then
                    echo "返回上層"
                    sleep 1
                    continue
                fi
                local ok=0 fail=0
                for n in "${stop_units[@]}"; do
                    if _unit_try_stop "$n"; then
                        ok=$((ok + 1))
                    else
                        fail=$((fail + 1))
                    fi
                done
                echo "停止結果：成功=$ok / 失敗=$fail"
                ui_pause
                ;;
            6)
                local -a restart_units=()
                mapfile -t restart_units < <(_pick_existing_unit_files_multi "重新啟動單元" container pod network volume image device)
                if [ "${#restart_units[@]}" -eq 0 ]; then
                    echo "返回上層"
                    sleep 1
                    continue
                fi
                local ok=0 fail=0
                for n in "${restart_units[@]}"; do
                    if _unit_try_restart "$n"; then
                        echo "✅ 已送出重啟：$n（啟動中，可用「查看單元日誌」追蹤）"
                        ok=$((ok + 1))
                    else
                        tgdb_warn "重啟失敗：$n（請檢查單元或日誌）"
                        fail=$((fail + 1))
                    fi
                done
                echo "重啟結果：成功=$ok / 失敗=$fail"
                ui_pause
                ;;
            7)
                local -a remove_units=()
                mapfile -t remove_units < <(_pick_existing_unit_files_multi "移除單元" container network volume pod device kube)
                if [ "${#remove_units[@]}" -eq 0 ]; then
                    echo "返回上層"
                    sleep 1
                    continue
                fi
                local ok=0 fail=0
                for b in "${remove_units[@]}"; do
                    if _remove_quadlet_unit "$b"; then
                        ok=$((ok + 1))
                    else
                        fail=$((fail + 1))
                    fi
                done
                echo "移除結果：成功=$ok / 失敗=$fail"
                ui_pause
                ;;
            8) podman_exec_container_menu ;;
            9) podman_images_menu ;;
            10) podman_networks_menu ;;
            11) podman_volumes_menu ;;
            12) podman_cleanup_menu ;;
            13) podman_auto_update_menu ;;
            14) containers_config_menu ;;
            d) uninstall_podman_environment ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

# ---- 清理 ----
podman_cleanup_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    if ui_confirm_yn "是否清除孤立容器、網路、映像、卷？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
        _podman_cleanup_resources
        echo "✅ 清理完成"
    else
        echo "已取消"
    fi
    ui_pause
}

# 將輸入字串拆成多個目標（支援空白或逗號分隔）。
_podman_parse_multi_targets() {
    local raw="${1:-}"
    local -a tokens=()
    local token

    raw="${raw//,/ }"
    read -r -a tokens <<< "$raw"
    for token in "${tokens[@]}"; do
        [ -n "$token" ] && printf '%s\n' "$token"
    done
}

_podman_batch_remove_targets() {
    local label="$1" remove_fn="$2"
    shift 2
    local -a targets=("$@")
    local ok=0 fail=0
    local target

    if [ "${#targets[@]}" -eq 0 ]; then
        tgdb_warn "未提供要移除的${label}"
        return 1
    fi

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

_podman_remove_image_target() { podman rmi -f "$1"; }
_podman_remove_network_target() { podman network rm "$1"; }
_podman_remove_volume_target() { podman volume rm "$1"; }

_podman_list_all_image_targets() {
    podman images --format '{{.ID}}' 2>/dev/null | awk 'NF && !seen[$0]++'
}

_podman_list_all_network_targets() {
    podman network ls --format '{{.Name}}' 2>/dev/null | awk 'NF'
}

_podman_list_all_volume_targets() {
    podman volume ls --format '{{.Name}}' 2>/dev/null | awk 'NF'
}

# ---- 網路管理 ----
podman_networks_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 網路管理 ❖"
        echo "=================================="
        echo "--- 當前網路 ---"
        podman network ls || true
        echo "----------------------------------"
        echo "1. 建立網路 (podman network create)"
        echo "2. 刪除網路（可多輸入）"
        echo "3. 全部移除網路"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-3]: " c
        case "$c" in
            1)
                read -r -e -p "網路名稱: " net
                [ -n "$net" ] && podman network create "$net"
                ui_pause "按鍵返回..."
                ;;
            2)
                local net_input
                local -a nets=()
                read -r -e -p "網路名稱或 ID（可一次輸入多個，以空白或逗號分隔）: " net_input
                mapfile -t nets < <(_podman_parse_multi_targets "$net_input")
                if [ "${#nets[@]}" -eq 0 ]; then
                    tgdb_warn "未輸入任何網路"
                else
                    _podman_batch_remove_targets "網路" _podman_remove_network_target "${nets[@]}"
                fi
                ui_pause "按鍵返回..."
                ;;
            3)
                local -a all_nets=()
                mapfile -t all_nets < <(_podman_list_all_network_targets)
                if [ "${#all_nets[@]}" -eq 0 ]; then
                    echo "目前沒有可移除的網路。"
                    ui_pause "按鍵返回..."
                    continue
                fi
                if ui_confirm_yn "確定要全部移除目前列出的網路（共 ${#all_nets[@]} 個）？(y/N，預設 Y，輸入 0 取消): " "Y"; then
                    _podman_batch_remove_targets "網路" _podman_remove_network_target "${all_nets[@]}"
                else
                    echo "已取消"
                fi
                ui_pause "按鍵返回..."
                ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

# ---- 卷管理 ----
podman_volumes_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 卷管理 ❖"
        echo "=================================="
        echo "--- 當前卷 ---"
        podman volume ls || true
        echo "----------------------------------"
        echo "1. 建立卷 (podman volume create)"
        echo "2. 刪除卷（可多輸入）"
        echo "3. 全部移除卷"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-3]: " c
        case "$c" in
            1)
                read -r -e -p "卷名稱: " vol
                [ -n "$vol" ] && podman volume create "$vol"
                ui_pause "按鍵返回..."
                ;;
            2)
                local vol_input
                local -a vols=()
                read -r -e -p "卷名稱或 ID（可一次輸入多個，以空白或逗號分隔）: " vol_input
                mapfile -t vols < <(_podman_parse_multi_targets "$vol_input")
                if [ "${#vols[@]}" -eq 0 ]; then
                    tgdb_warn "未輸入任何卷"
                else
                    _podman_batch_remove_targets "卷" _podman_remove_volume_target "${vols[@]}"
                fi
                ui_pause "按鍵返回..."
                ;;
            3)
                local -a all_vols=()
                mapfile -t all_vols < <(_podman_list_all_volume_targets)
                if [ "${#all_vols[@]}" -eq 0 ]; then
                    echo "目前沒有可移除的卷。"
                    ui_pause "按鍵返回..."
                    continue
                fi
                if ui_confirm_yn "確定要全部移除目前列出的卷（共 ${#all_vols[@]} 個）？(y/N，預設 Y，輸入 0 取消): " "Y"; then
                    _podman_batch_remove_targets "卷" _podman_remove_volume_target "${all_vols[@]}"
                else
                    echo "已取消"
                fi
                ui_pause "按鍵返回..."
                ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

# ---- 容器互動 ----
_podman_pick_running_container() {
    if ! command -v podman >/dev/null 2>&1; then
        tgdb_fail "Podman 未安裝" 1 || return $?
    fi

    mapfile -t __containers < <(_podman_collect_container_records running)
    if [ "${#__containers[@]}" -eq 0 ]; then
        tgdb_warn "目前沒有任何運行中的容器"
        return 1
    fi

    echo "--- 運行中的容器 ---" >&2
    local i
    for ((i=0; i<${#__containers[@]}; i++)); do
        IFS=$'\t' read -r scope id name image status <<< "${__containers[$i]}"
        printf "%2d) %s [%s] (%s) [%s]\n" $((i+1)) "$name" "$(_podman_scope_display_name "$scope")" "$image" "$status" >&2
    done
    echo " 0) 返回" >&2

    local pick
    if ! ui_prompt_index pick "請輸入容器序號 [0-${#__containers[@]}]: " 1 "${#__containers[@]}" "" 0; then
        return 1
    fi
    local idx=$((pick-1))

    printf '%s\n' "${__containers[$idx]}"
}

podman_exec_container_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    local row scope id name image status
    row=$(_podman_pick_running_container) || { echo "返回上一層"; sleep 1; return 1; }

    IFS=$'\t' read -r scope id name image status <<< "$row"
    clear
    echo "=================================="
    echo "❖ 進入容器 Shell ❖"
    echo "=================================="
    echo "容器名稱：$name"
    echo "範圍：$(_podman_scope_display_name "$scope")"
    echo "映像：$image"
    echo "狀態：$status"
    echo "----------------------------------"
    echo "提示：已進入容器環境，輸入 exit 可退出並返回 TGDB。"
    echo "=================================="

    if _podman_podman_cmd "$scope" exec -it "$id" /bin/sh; then
        echo
        echo "✅ 已離開容器：$name"
        ui_pause
    else
        tgdb_err "無法進入容器，請確認容器內是否有 /bin/sh"
        ui_pause
        return 1
    fi
}

# ---- 映像選單 ----
podman_images_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 映像管理 ❖"
        echo "=================================="
        echo "--- 當前映像 ---"
        podman images || true
        echo "----------------------------------"
        echo "1. 拉取映像 (podman pull)"
        echo "2. 刪除映像（可多輸入）"
        echo "3. 全部移除映像"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-3]: " c
        case "$c" in
            1)
                read -r -e -p "映像 (例如 docker.io/library/alpine:latest): " img
                [ -n "$img" ] && podman pull "$img"
                ui_pause "按鍵返回..."
                ;;
            2)
                local img_input
                local -a imgs=()
                read -r -e -p "映像（NAME:TAG 或 ID，可一次輸入多個，以空白或逗號分隔）: " img_input
                mapfile -t imgs < <(_podman_parse_multi_targets "$img_input")
                if [ "${#imgs[@]}" -eq 0 ]; then
                    tgdb_warn "未輸入任何映像"
                else
                    _podman_batch_remove_targets "映像" _podman_remove_image_target "${imgs[@]}"
                fi
                ui_pause "按鍵返回..."
                ;;
            3)
                local -a all_imgs=()
                mapfile -t all_imgs < <(_podman_list_all_image_targets)
                if [ "${#all_imgs[@]}" -eq 0 ]; then
                    echo "目前沒有可移除的映像。"
                    ui_pause "按鍵返回..."
                    continue
                fi
                if ui_confirm_yn "確定要全部移除目前列出的映像（共 ${#all_imgs[@]} 個）？(y/N，預設 Y，輸入 0 取消): " "Y"; then
                    _podman_batch_remove_targets "映像" _podman_remove_image_target "${all_imgs[@]}"
                else
                    echo "已取消"
                fi
                ui_pause "按鍵返回..."
                ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

podman_auto_update_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "此功能需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ 容器自動更新（podman auto-update）❖"
        echo "=================================="
        local timer_enabled="unknown" timer_active="unknown"
        if command -v systemctl >/dev/null 2>&1; then
            timer_enabled="$(systemctl --user is-enabled podman-auto-update.timer 2>/dev/null || true)"
            timer_active="$(systemctl --user is-active podman-auto-update.timer 2>/dev/null || true)"
            [ -z "$timer_enabled" ] && timer_enabled="unknown"
            [ -z "$timer_active" ] && timer_active="unknown"
        else
            timer_enabled="not_supported"
            timer_active="not_supported"
        fi
        echo "podman-auto-update.timer：啟用=$timer_enabled / 狀態=$timer_active"
        echo "----------------------------------"
        echo "說明："
        echo "- 本功能會執行一次：podman auto-update"
        echo "- 需容器本身已設定 AutoUpdate 才會被更新（例如 Quadlet .container 內 [Container] 加上 AutoUpdate=registry）。"
        echo "- podman-auto-update.timer 可選擇啟用，做成定期更新。"
        echo ""
        tgdb_warn "警語（務必閱讀）："
        echo "- 上游映像更新可能造成不相容，導致容器更新後『無法啟動/無法運行』。"
        echo "- 若 TGDB 專案/設定尚未同步更新（例如反向代理、環境變數、資料庫版本），更容易發生更新後啟動失敗。"
        echo "- 建議：先備份、避免使用 latest、優先固定版本 tag，並在測試環境驗證。"
        echo "----------------------------------"
        echo "1. 立即執行一次 podman auto-update（建議先看警語）"
        echo "2. 啟用 podman-auto-update.timer（定期更新）"
        echo "3. 停用 podman-auto-update.timer"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-3]: " c
        case "$c" in
            1)
                if ! command -v podman >/dev/null 2>&1; then
                    tgdb_err "Podman 未安裝，無法執行 podman auto-update"
                    ui_pause
                    continue
                fi
                if ui_confirm_yn "⚠️ 可能因映像更新/不相容導致服務無法運行，確定要立即執行 podman auto-update 嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
                    echo "⏳ 正在執行：podman auto-update"
                    if podman auto-update; then
                        echo "✅ 已完成：podman auto-update"
                        echo "提示：若服務異常，請用 systemctl --user status <單元> 與 journalctl --user -u <單元> 檢查。"
                    else
                        tgdb_warn "podman auto-update 執行失敗，請查看輸出訊息與日誌後再重試。"
                    fi
                else
                    echo "已取消"
                fi
                ui_pause
                ;;
            2)
                _podman_auto_update_timer_enable || true
                echo "提示：可用 journalctl --user -u podman-auto-update.service 查看更新紀錄。"
                ui_pause
                ;;
            3)
                if ui_confirm_yn "確定要停用 podman-auto-update.timer？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
                    _podman_auto_update_timer_disable || true
                else
                    echo "已取消"
                fi
                ui_pause
                ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}

# ---- containers 設定（policy.json / registries.conf）----
containers_config_menu() {
    if ! ui_is_interactive; then
        tgdb_fail "containers 設定需要互動式終端（TTY）。" 2 || return $?
    fi

    while true; do
        clear
        echo "=================================="
        echo "❖ containers 設定（policy.json / registries.conf）❖"
        echo "=================================="
        echo "警語：不當修改 policy.json 可能允許不受信任映像，請謹慎操作。"
        echo "建議：使用者層級優先（~/.config/containers），系統層級需 sudo。"
        echo "----------------------------------"
        echo "1. 檢查/修復缺失（安裝 containers-common + 同步到使用者目錄）"
        echo "2. 編輯使用者 policy.json"
        echo "3. 編輯使用者 registries.conf"
        echo "4. 編輯系統 policy.json（需 sudo）"
        echo "5. 編輯系統 registries.conf（需 sudo）"
        echo "----------------------------------"
        echo "0. 返回"
        echo "=================================="
        read -r -e -p "請輸入選擇 [0-5]: " c
        case "$c" in
            1)
                _ensure_containers_configs
                _copy_system_to_user_if_missing
                _create_safe_defaults_if_missing
                ui_pause "完成，按任意鍵返回..."
                ;;
            2)
                _copy_system_to_user_if_missing
                _create_safe_defaults_if_missing
                if ! ensure_editor; then
                    tgdb_err "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。"
                    ui_pause
                    continue
                fi
                "$EDITOR" "$( _user_policy )"
                ;;
            3)
                _copy_system_to_user_if_missing
                _create_safe_defaults_if_missing
                if ! ensure_editor; then
                    tgdb_err "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。"
                    ui_pause
                    continue
                fi
                "$EDITOR" "$( _user_registries )"
                ;;
            4)
                sudo mkdir -p "$( _system_containers_dir )"
                if [ ! -f "$( _system_policy )" ]; then
                    tgdb_warn "系統 policy.json 缺失，嘗試安裝 containers-common..."
                    _ensure_containers_common_installed || true
                    sudo touch "$( _system_policy )"
                fi
                if ! ensure_editor; then
                    tgdb_err "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。"
                    ui_pause
                    continue
                fi
                sudo "$EDITOR" "$( _system_policy )"
                ;;
            5)
                sudo mkdir -p "$( _system_containers_dir )"
                if [ ! -f "$( _system_registries )" ]; then
                    tgdb_warn "系統 registries.conf 缺失，嘗試安裝 containers-common..."
                    _ensure_containers_common_installed || true
                    sudo touch "$( _system_registries )"
                fi
                if ! ensure_editor; then
                    tgdb_err "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。"
                    ui_pause
                    continue
                fi
                sudo "$EDITOR" "$( _system_registries )"
                ;;
            0) return ;;
            *) echo "無效選項"; sleep 1 ;;
        esac
    done
}
