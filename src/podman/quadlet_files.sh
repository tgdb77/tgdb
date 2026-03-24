#!/bin/bash

# Podman：Quadlet 檔案操作（同步/新增/編輯/移除）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_sync_quadlet_unit_to_config() {
    local fname="$1"
    [ -z "$fname" ] && return 0
    local src
    src="$(rm_user_unit_path "$fname")"
    [ -f "$src" ] || return 0

    local ext subdir
    ext="${fname##*.}"
    subdir="$(rm_quadlet_subdir_by_ext "$ext")" || return 0

    local dest_dir
    dest_dir="$(rm_persist_quadlet_subdir_dir "$subdir")"
    mkdir -p "$dest_dir"
    if cp "$src" "$dest_dir/$fname"; then
        echo "✅ 已同步單元到設定目錄：$dest_dir/$fname"
    else
        tgdb_warn "無法同步單元到設定目錄：$dest_dir"
    fi
}

_create_or_edit_quadlet_unit() {
    local name type_idx ext fname
    read -r -e -p "請輸入單元檔名（不含副檔名，如 myapp）: " name
    if [ -z "$name" ]; then tgdb_fail "檔名不可為空" 1 || return $?; fi

    echo "選擇單元類型："
    echo "  1) container(掛載卷需要有目錄)"
    echo "  2) network"
    echo "  3) volume"
    echo "  4) pod"
    echo "  5) device"
    read -r -e -p "請輸入選擇 [1-5]: " type_idx
    case "$type_idx" in
        1) ext="container" ;;
        2) ext="network" ;;
        3) ext="volume" ;;
        4) ext="pod" ;;
        5) ext="device" ;;
        *) tgdb_fail "無效選擇" 1 || return $? ;;
    esac

    fname="$name.$ext"

    if [ "$ext" = "container" ]; then
        if [ -z "${TGDB_DIR:-}" ]; then
            tgdb_warn "無法取得 TGDB 目錄設定，略過實例資料夾建立。"
        else
            local instance_dir="$TGDB_DIR/$name"
            if [ -d "$instance_dir" ]; then
                echo "ℹ️ 實例資料夾已存在：$instance_dir"
            else
                if mkdir -p "$instance_dir" 2>/dev/null; then
                    echo "✅ 已建立實例資料夾：$instance_dir"
                else
                    tgdb_warn "無法建立實例資料夾：$instance_dir（請確認權限）"
                fi
            fi
        fi
    fi

    if ! ensure_editor; then
        tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || return $?
    fi
    "$EDITOR" "$(rm_user_unit_path "$fname")"
    _systemctl_user_try daemon-reload || true
    if _unit_try_enable_now "$fname"; then
        _sync_quadlet_unit_to_config "$fname"
        echo "✅ 已啟用並送出啟動：$fname（啟動中，可用「查看單元日誌」追蹤）"
    else
        _sync_quadlet_unit_to_config "$fname"
        tgdb_warn "已保存，但啟用/啟動可能失敗，請檢查單元內容或日誌。"
    fi
}

_pick_existing_unit_file() {
    mapfile -t __units < <(_list_user_units "$@")
    if [ "${#__units[@]}" -eq 0 ]; then
        tgdb_warn "目前沒有任何單元檔可編輯"
        return 1
    fi
    echo "--- 現有單元 ---" >&2
    local i
    for ((i=0; i<${#__units[@]}; i++)); do
        printf "%2d) %s\n" $((i+1)) "${__units[$i]}" >&2
    done
    local pick
    read -r -e -p "請輸入序號或檔名：" pick
    if [ -z "$pick" ]; then
        return 1
    fi
    if [[ "$pick" =~ ^[0-9]+$ ]]; then
        local idx=$((pick-1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#__units[@]} ]; then
            printf '%s\n' "${__units[$idx]}"
            return 0
        fi
        tgdb_fail "序號超出範圍" 1 || return $?
    fi
    printf '%s\n' "$pick"
}

_pick_existing_unit_files_multi() {
    local action_label="$1"
    shift

    local -a units=()
    mapfile -t units < <(_list_user_units "$@")
    if [ "${#units[@]}" -eq 0 ]; then
        tgdb_warn "目前沒有任何單元檔可操作"
        return 1
    fi

    echo "--- 現有單元 ---" >&2
    local i
    for ((i=0; i<${#units[@]}; i++)); do
        printf "%2d) %s\n" $((i+1)) "${units[$i]}" >&2
    done
    echo "提示：可多選（空白或逗號分隔）；輸入 a 代表全部；輸入 0 返回。" >&2

    local pick_raw
    read -r -e -p "請輸入序號或檔名：" pick_raw
    pick_raw="$(_podman_trim_ws "$pick_raw")"
    [ -z "$pick_raw" ] && return 1
    [ "$pick_raw" = "0" ] && return 1

    local raw_tokens="${pick_raw//,/ }"
    local -a tokens=()
    read -r -a tokens <<< "$raw_tokens"

    local -a selected=()
    local token lower resolved idx
    local all_selected=false

    for token in "${tokens[@]}"; do
        [ -n "$token" ] || continue
        lower="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
        case "$lower" in
            a|all|"*")
                all_selected=true
                break
                ;;
        esac

        if [[ "$token" =~ ^[0-9]+$ ]]; then
            idx=$((token-1))
            if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#units[@]}" ]; then
                tgdb_fail "序號超出範圍：$token" 1 || return $?
            fi
            resolved="${units[$idx]}"
        else
            resolved=""
            local u
            for u in "${units[@]}"; do
                if [ "$u" = "$token" ]; then
                    resolved="$u"
                    break
                fi
            done
            if [ -z "$resolved" ]; then
                tgdb_fail "找不到單元：$token" 1 || return $?
            fi
        fi

        selected+=("$resolved")
    done

    if [ "$all_selected" = true ]; then
        selected=("${units[@]}")
    fi

    mapfile -t selected < <(printf '%s\n' "${selected[@]}" | awk 'NF && !seen[$0]++')
    if [ "${#selected[@]}" -eq 0 ]; then
        tgdb_warn "未選擇任何單元"
        return 1
    fi

    if [ "${#selected[@]}" -eq "${#units[@]}" ]; then
        if ! ui_confirm_yn "你選擇了全部單元（共 ${#selected[@]} 個），確定要${action_label}嗎？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
            echo "已取消" >&2
            return 1
        fi
    fi

    printf '%s\n' "${selected[@]}"
}

_podman_trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_podman_src_dir() {
    if [ -n "${SRC_DIR:-}" ] && [ -d "${SRC_DIR:-}" ]; then
        printf '%s\n' "$SRC_DIR"
        return 0
    fi
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}

_podman_appspec_ensure_loaded() {
    declare -F appspec_get >/dev/null 2>&1 && return 0

    local src_dir appspec_file
    src_dir="$(_podman_src_dir)"
    appspec_file="$src_dir/apps/app_spec.sh"
    if [ -f "$appspec_file" ]; then
        # shellcheck disable=SC1090 # 依 repo 結構載入 AppSpec
        source "$appspec_file"
        return 0
    fi
    return 1
}

_podman_appspec_ensure_exec_loaded() {
    _podman_appspec_ensure_loaded || return 1
    declare -F _appspec_config_defs >/dev/null 2>&1 && return 0

    local src_dir base_file deploy_file records_file
    src_dir="$(_podman_src_dir)"

    base_file="$src_dir/apps/app_spec_exec/base.sh"
    deploy_file="$src_dir/apps/app_spec_exec/deploy.sh"
    records_file="$src_dir/apps/app_spec_exec/records.sh"

    [ -f "$base_file" ] || return 1
    [ -f "$deploy_file" ] || return 1

    # shellcheck disable=SC1090 # 依 repo 結構載入 AppSpec 執行器
    source "$base_file"
    # shellcheck disable=SC1090 # 依 repo 結構載入 AppSpec 執行器
    source "$deploy_file"

    # records.sh 不是必須，但若存在可用來產生更一致的提示（例如 config label）
    if [ -f "$records_file" ]; then
        # shellcheck disable=SC1090 # 依 repo 結構載入 AppSpec 執行器
        source "$records_file"
    fi

    declare -F _appspec_config_defs >/dev/null 2>&1
}

_podman_extract_app_label_from_unit_file() {
    local unit_file="$1"
    [ -r "$unit_file" ] || return 0
    awk '
        /^[[:space:]]*Label[[:space:]]*=/ {
          line=$0
          sub(/^[[:space:]]*Label[[:space:]]*=[[:space:]]*/, "", line)
          sub(/[[:space:]]*(#.*)?$/, "", line)
          gsub(/^"|"$/, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          if (line ~ /^app=/) {
            sub(/^app=/, "", line)
            if (line != "") { print line; exit }
          }
        }
      ' "$unit_file"
}

_podman_detect_app_service_for_unit_file() {
    local fname="$1"
    local unit_path="$2"

    local service=""
    service="$(_podman_extract_app_label_from_unit_file "$unit_path")"
    if [ -n "$service" ]; then
        printf '%s\n' "$service"
        return 0
    fi

    local ext="${fname##*.}"
    if [ "$ext" != "pod" ]; then
        printf '%s\n' ""
        return 0
    fi

    local base="${fname%.pod}"
    local member
    while IFS= read -r member; do
        [ -n "$member" ] || continue
        service="$(_podman_extract_app_label_from_unit_file "$(rm_user_unit_path "$member")")"
        if [ -n "$service" ]; then
            printf '%s\n' "$service"
            return 0
        fi
    done < <(_list_pod_member_container_unit_files "$base" 2>/dev/null || true)

    printf '%s\n' ""
    return 0
}

_podman_appspec_collect_unit_suffixes() {
    local service="$1"

    _podman_appspec_ensure_loaded || return 1

    local raw=""
    raw="$(appspec_get_all "$service" "unit" 2>/dev/null || true)"
    [ -n "$raw" ] || return 1

    awk -F'|' '
        {
          for (i=2; i<=NF; i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
            if ($i ~ /^suffix=/) {
              sub(/^suffix=/, "", $i)
              if ($i != "") print $i
            }
          }
        }
      ' <<<"$raw" | awk 'NF && !seen[$0]++'
}

_podman_infer_app_instance_from_unit_filename() {
    local service="$1"
    local fname="$2"

    local -a suffixes=()
    local suffix
    while IFS= read -r suffix; do
        [ -n "$suffix" ] && suffixes+=("$suffix")
    done < <(_podman_appspec_collect_unit_suffixes "$service" 2>/dev/null || true)

    local best="" best_len=0
    for suffix in "${suffixes[@]}"; do
        case "$fname" in
            *"$suffix")
                local base="${fname%"$suffix"}"
                [ -n "$base" ] || continue
                local len=${#suffix}
                if [ "$len" -gt "$best_len" ]; then
                    best_len="$len"
                    best="$base"
                fi
                ;;
        esac
    done

    if [ "$best_len" -gt 0 ] && [ -n "$best" ]; then
        printf '%s\n' "$best"
        return 0
    fi

    printf '%s\n' "${fname%.*}"
    return 0
}

_podman_instance_rel_path_is_safe() {
    local p="$1"
    [ -n "${p:-}" ] || return 1
    case "$p" in
        /*|*\\*|*..*) return 1 ;;
    esac
    return 0
}

_podman_ensure_tgdb_dir() {
    if [ -n "${TGDB_DIR:-}" ]; then
        return 0
    fi
    if declare -F load_system_config >/dev/null 2>&1; then
        load_system_config || true
    fi
    [ -n "${TGDB_DIR:-}" ]
}

_podman_collect_app_instance_config_paths_from_appspec() {
    local service="$1"
    local instance="$2"

    _podman_appspec_ensure_exec_loaded || return 0
    _podman_ensure_tgdb_dir || return 0

    local instance_dir="$TGDB_DIR/$instance"
    [ -d "$instance_dir" ] || return 0

    # shellcheck disable=SC2034 # 其他欄位僅為配合 _appspec_config_defs 介面
    local -a cfg_dests=() cfg_tpls=() cfg_modes=() cfg_labels=()
    _appspec_config_defs "$service" cfg_dests cfg_tpls cfg_modes cfg_labels || return 0
    [ ${#cfg_dests[@]} -gt 0 ] || return 0

    local dest
    for dest in "${cfg_dests[@]}"; do
        dest="$(_podman_trim_ws "$dest")"
        [ -n "$dest" ] || continue
        _podman_instance_rel_path_is_safe "$dest" || continue

        local path="$instance_dir/$dest"
        mkdir -p "$(dirname "$path")" 2>/dev/null || true
        printf '%s\n' "$path"
    done
}

_podman_collect_app_instance_edit_files_from_appspec() {
    local service="$1"
    local instance="$2"

    _podman_appspec_ensure_loaded || return 0
    _podman_ensure_tgdb_dir || return 0

    local instance_dir="$TGDB_DIR/$instance"
    [ -d "$instance_dir" ] || return 0

    local raw=""
    raw="$(appspec_get_all "$service" "edit_files" 2>/dev/null || true)"
    [ -n "$raw" ] || return 0

    local line seg
    while IFS= read -r line; do
        line="$(_podman_trim_ws "$line")"
        [ -n "$line" ] || continue
        for seg in $line; do
            seg="$(_podman_trim_ws "$seg")"
            [ -n "$seg" ] || continue
            _podman_instance_rel_path_is_safe "$seg" || continue

            local path="$instance_dir/$seg"
            mkdir -p "$(dirname "$path")" 2>/dev/null || true
            printf '%s\n' "$path"
        done
    done <<< "$raw"
}

_podman_collect_env_files_from_unit_file() {
    local unit_path="$1"
    [ -n "${unit_path:-}" ] || return 0
    [ -r "$unit_path" ] || return 0

    awk '
        /^[[:space:]]*EnvironmentFile[[:space:]]*=/ {
          line=$0
          sub(/^[[:space:]]*EnvironmentFile[[:space:]]*=[[:space:]]*/, "", line)
          sub(/[[:space:]]*(#.*)?$/, "", line)
          gsub(/^"|"$/, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

          n = split(line, parts, /[[:space:]]+/)
          for (i = 1; i <= n; i++) {
            p = parts[i]
            if (p == "") continue
            if (substr(p, 1, 1) == "-") p = substr(p, 2)
            if (p == "") continue
            if (p ~ /[*?\[]/) continue
            if (p ~ /^\//) print p
          }
        }
      ' "$unit_path" | awk 'NF && !seen[$0]++'
}

_podman_collect_env_files_for_service_instance() {
    local service="$1"
    local instance="$2"
    local unit_path_hint="${3:-}"

    _podman_appspec_ensure_loaded || return 0

    local user_units_dir
    user_units_dir="$(rm_user_units_dir)"
    [ -d "$user_units_dir" ] || return 0

    local -A unit_seen=()
    local -a unit_paths=()
    if [ -n "$unit_path_hint" ] && [ -f "$unit_path_hint" ]; then
        unit_seen["$unit_path_hint"]=1
        unit_paths+=("$unit_path_hint")
    fi

    local quadlet_type
    quadlet_type="$(appspec_get "$service" "quadlet_type" "")"
    if [ "$quadlet_type" = "multi" ]; then
        local suffix path
        while IFS= read -r suffix; do
            [ -n "$suffix" ] || continue
            path="$user_units_dir/${instance}${suffix}"
            [ -f "$path" ] || continue
            if [ -z "${unit_seen[$path]+x}" ]; then
                unit_seen["$path"]=1
                unit_paths+=("$path")
            fi
        done < <(_podman_appspec_collect_unit_suffixes "$service" 2>/dev/null || true)
    else
        local path="$user_units_dir/${instance}.container"
        if [ -f "$path" ] && [ -z "${unit_seen[$path]+x}" ]; then
            unit_seen["$path"]=1
            unit_paths+=("$path")
        fi
    fi

    local -A env_seen=()
    local up env
    for up in "${unit_paths[@]}"; do
        while IFS= read -r env; do
            [ -n "$env" ] || continue
            if [ -z "${env_seen[$env]+x}" ]; then
                env_seen["$env"]=1
                printf '%s\n' "$env"
            fi
        done < <(_podman_collect_env_files_from_unit_file "$up" 2>/dev/null || true)
    done
}

_podman_collect_app_config_paths_for_instance() {
    local service="$1"
    local instance="$2"
    local unit_path="${3:-}"

    local -A seen=()
    local p

    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -z "${seen[$p]+x}" ]; then
            seen["$p"]=1
            printf '%s\n' "$p"
        fi
    done < <(
        _podman_collect_app_instance_config_paths_from_appspec "$service" "$instance"
        _podman_collect_app_instance_edit_files_from_appspec "$service" "$instance"
        _podman_collect_env_files_for_service_instance "$service" "$instance" "$unit_path"
    )
}

_edit_existing_unit_and_reload_restart() {
    local fname
    fname=$(_pick_existing_unit_file container network volume pod device kube) || return 1
    if [ -z "$fname" ]; then tgdb_fail "檔名不可為空" 1 || return $?; fi
    if ! ensure_editor; then
        tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || return $?
    fi

    local unit_path
    unit_path="$(rm_user_unit_path "$fname")"

    local -a edit_files=("$unit_path")
    local service instance
    service="$(_podman_detect_app_service_for_unit_file "$fname" "$unit_path" 2>/dev/null || true)"
    instance="${fname%.*}"
    if [ -n "$service" ]; then
        instance="$(_podman_infer_app_instance_from_unit_filename "$service" "$fname" 2>/dev/null || echo "$instance")"
    fi

    if [ -n "$service" ] && [ -n "$instance" ]; then
        local -a cfg_files=()
        mapfile -t cfg_files < <(_podman_collect_app_config_paths_for_instance "$service" "$instance" "$unit_path")
        if [ ${#cfg_files[@]} -gt 0 ]; then
            local prompt
            prompt="偵測到應用：$service / 實例：$instance；是否同時編輯設定檔（${#cfg_files[@]} 個）？(Y/n，預設 Y，輸入 0 取消): "
            if ui_confirm_yn "$prompt" "Y"; then
                edit_files+=("${cfg_files[@]}")
            else
                local rc=$?
                if [ "$rc" -eq 2 ]; then
                    echo "操作已取消。"
                    return 1
                fi
            fi
        else
            tgdb_warn "已偵測到應用：$service，但找不到可編輯的設定檔：$instance（可能尚未部署、TGDB_DIR/$instance 不存在、單元未設定 EnvironmentFile=，或 app.spec 未定義 config=/edit_files=）"
        fi
    fi

    local -a need_unshare=()
    local -a owned_by_root=()
    local p
    for p in "${edit_files[@]}"; do
        if [ -e "$p" ]; then
            if [ ! -w "$p" ]; then
                need_unshare+=("$p")
                local uid
                uid="$(stat -c '%u' "$p" 2>/dev/null || echo "")"
                if [ "$uid" = "0" ]; then
                    owned_by_root+=("$p")
                fi
            fi
        else
            local parent
            parent="$(dirname "$p")"
            if [ -d "$parent" ] && [ ! -w "$parent" ]; then
                need_unshare+=("$p")
            fi
        fi
    done

    if [ ${#need_unshare[@]} -gt 0 ]; then
        if [ ${#owned_by_root[@]} -gt 0 ]; then
            tgdb_warn "偵測到以下檔案疑似由 root 擁有（uid=0），podman unshare 可能仍無法編輯："
            printf ' - %s\n' "${owned_by_root[@]}" >&2
            tgdb_warn "建議改用 sudoedit，或先調整檔案擁有者後再編輯。"
        fi

        tgdb_warn "偵測到部分檔案無法直接寫入，可能是 rootless UID 映射造成，將嘗試用 podman unshare 開啟編輯器："
        printf ' - %s\n' "${need_unshare[@]}" >&2
        if ! podman unshare "$EDITOR" "${edit_files[@]}"; then
            tgdb_warn "podman unshare 開啟編輯器失敗，將直接開啟編輯器（可能仍無法儲存）。"
            "$EDITOR" "${edit_files[@]}"
        fi
    else
        "$EDITOR" "${edit_files[@]}"
    fi
    _systemctl_user_try daemon-reload || true
    _unit_try_enable_now "$fname" || true
    if _unit_try_restart "$fname"; then
        echo "✅ 已重整並送出重啟：$fname（啟動中，可用「查看單元日誌」追蹤）"
    else
        if _unit_try_enable_now "$fname"; then
            echo "✅ 已重整並送出啟動：$fname（啟動中，可用「查看單元日誌」追蹤）"
        else
            tgdb_warn "已保存並重整，但重啟/啟動失敗，請檢查單元或日誌。"
        fi
    fi
}

_remove_quadlet_unit() {
    local token="$1"
    if [ -z "$token" ]; then tgdb_fail "檔名不可為空" 1 || return $?; fi

    local user_units_dir
    user_units_dir="$(rm_user_units_dir)"

    # 相容：若使用者輸入的是 pod 的 systemd 單元名稱（例如 pod-xxx.service），嘗試對應回 *.pod 檔案。
    if [ ! -f "$user_units_dir/$token" ]; then
        local pod_base_from_service=""
        pod_base_from_service="$(_pod_base_from_token "$token" 2>/dev/null || true)"
        if [ -n "$pod_base_from_service" ] && [ -f "$user_units_dir/${pod_base_from_service}.pod" ]; then
            token="${pod_base_from_service}.pod"
        fi
    fi

    local target_file=""
    if [ -f "$user_units_dir/$token" ]; then
        target_file="$user_units_dir/$token"
    else
        if [[ "$token" != *.* ]]; then
            mapfile -t matches < <(find "$user_units_dir" -maxdepth 1 \( -type f -o -type l \) -name "$token.*" -exec basename {} \; 2>/dev/null | sort)
            if [ "${#matches[@]}" -eq 1 ]; then
                target_file="$user_units_dir/${matches[0]}"
            elif [ "${#matches[@]}" -gt 1 ]; then
                echo "找到多個匹配，請指定完整檔名："
                printf ' - %s\n' "${matches[@]}"
                return 1
            fi
        fi
    fi

    if [ -z "$target_file" ]; then
        tgdb_warn "找不到單元檔：$user_units_dir/$token"
        return 1
    fi

    local fname base ext
    fname=$(basename "$target_file")
    base="${fname%.*}"
    ext="${fname##*.}"

    if [[ "$ext" = "pod" ]]; then
        local -a members=()
        mapfile -t members < <(_list_pod_member_container_unit_files "$base")

        local -a all_units=()
        local u m
        while IFS= read -r u; do
            [ -n "$u" ] && all_units+=("$u")
        done < <(_resolve_unit_candidates "$fname")
        for m in "${members[@]}"; do
            while IFS= read -r u; do
                [ -n "$u" ] && all_units+=("$u")
            done < <(_resolve_unit_candidates "$m")
        done
        mapfile -t all_units < <(printf "%s\n" "${all_units[@]}" | awk 'NF && !seen[$0]++')

        for u in "${all_units[@]}"; do
            if [[ "$u" =~ \.service$ || "$u" =~ \.(container|network|volume|kube|pod)$ ]]; then
                _systemctl_user_try disable --now -- "$u" || true
            fi
        done
        _systemctl_user_try reset-failed || true

        if command -v podman >/dev/null 2>&1; then
            # 先嘗試移除整個 pod（含 infra/pause），再保險移除成員容器
            podman pod rm -f "$base" 2>/dev/null || true
            for m in "${members[@]}"; do
                local unit_path="$user_units_dir/$m"
                local cn=""
                cn="$(_container_name_from_unit_file "$unit_path" 2>/dev/null || true)"
                [ -n "$cn" ] || cn="${m%.container}"
                podman rm -f "$cn" 2>/dev/null || true
            done
        fi

        for m in "${members[@]}"; do
            rm -f "$user_units_dir/$m" 2>/dev/null || true
        done
        rm -f "$target_file" 2>/dev/null || true
        _systemctl_user_try daemon-reload || true

        if ui_is_interactive && [ -n "${TGDB_DIR:-}" ] && [ -d "$TGDB_DIR/$base" ]; then
            if ui_confirm_yn "是否同時刪除實例資料夾（$TGDB_DIR/$base）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
                podman unshare rm -rf "${TGDB_DIR:?}/$base" 2>/dev/null || true
            fi
        fi

        if [ "${#members[@]}" -gt 0 ]; then
            echo "✅ 已移除 Pod：$fname（並一併移除成員容器單元：${#members[@]} 個）"
        else
            echo "✅ 已移除 Pod：$fname"
        fi
        return 0
    fi

    local u
    while IFS= read -r u; do
        if [[ "$u" =~ \.service$ || "$u" =~ \.(container|network|volume|kube|pod)$ ]]; then
            _systemctl_user_try disable --now -- "$u" || true
        fi
    done < <(_resolve_unit_candidates "$fname")
    _systemctl_user_try reset-failed || true

    if [[ "$ext" = "container" ]]; then
        if command -v podman >/dev/null 2>&1; then
            local cn=""
            cn="$(_container_name_from_unit_file "$target_file" 2>/dev/null || true)"
            [ -n "$cn" ] || cn="$base"
            podman rm -f "$cn" 2>/dev/null || true
        fi
        if ui_is_interactive; then
            if ui_confirm_yn "是否同時刪除實例資料夾（$TGDB_DIR/$base）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
                rm -rf "${TGDB_DIR:?}/$base" 2>/dev/null || true
            fi
        else
            tgdb_warn "非互動模式略過刪除實例資料夾：$TGDB_DIR/$base"
        fi
    fi

    rm -f "$target_file"
    _systemctl_user_try daemon-reload || true
    echo "✅ 已移除：$fname"
}
