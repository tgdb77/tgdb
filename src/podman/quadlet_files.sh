#!/bin/bash

# Podman：Quadlet 檔案操作（同步/新增/編輯/移除）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_sync_quadlet_unit_to_config() {
    local fname="$1"
    [ -z "$fname" ] && return 0
    local record scope name src
    record="$(_podman_resolve_unit_records "$fname" 2>/dev/null | head -n 1 || true)"
    [ -n "$record" ] || return 0
    IFS=$'\t' read -r scope name src <<< "$record"
    [ -f "$src" ] || return 0

    local ext subdir
    ext="${name##*.}"
    subdir="$(rm_quadlet_subdir_by_ext "$ext")" || return 0

    local dest_dir
    dest_dir="$(rm_persist_quadlet_subdir_dir "$subdir")"
    mkdir -p "$dest_dir"

    local dest
    dest="$dest_dir/$name"
    if [ "$scope" = "system" ]; then
        # 用 sudo 讀取 system scope 單元，再以目前使用者寫入設定目錄（避免產生 root 擁有檔案）。
        if _podman_run_scope_cmd "$scope" cat "$src" 2>/dev/null | tee "$dest" >/dev/null 2>&1; then
            echo "✅ 已同步單元到設定目錄：$dest"
        else
            tgdb_warn "無法同步單元到設定目錄：$dest_dir"
        fi
        return 0
    fi

    if cp "$src" "$dest"; then
        echo "✅ 已同步單元到設定目錄：$dest"
    else
        tgdb_warn "無法同步單元到設定目錄：$dest_dir"
    fi
}

_create_or_edit_quadlet_unit() {
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    shift || true

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
        local runtime_dir
        runtime_dir="$(_podman_runtime_dir_for_scope "$scope")"
        if [ -z "${runtime_dir:-}" ]; then
            tgdb_warn "無法取得 TGDB 目錄設定，略過實例資料夾建立。"
        else
            local instance_dir="$runtime_dir/$name"
            if [ "$scope" = "system" ]; then
                if _podman_run_scope_cmd "$scope" test -d "$instance_dir" 2>/dev/null; then
                    echo "ℹ️ 實例資料夾已存在：$instance_dir"
                else
                    if _podman_run_scope_cmd "$scope" mkdir -p "$instance_dir" 2>/dev/null; then
                        echo "✅ 已建立實例資料夾：$instance_dir"
                    else
                        tgdb_warn "無法建立實例資料夾：$instance_dir（請確認權限）"
                    fi
                fi
            else
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
    fi

    if ! ensure_editor; then
        tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || return $?
    fi

    local unit_path
    unit_path="$(_podman_unit_path "$scope" "$fname")"
    _podman_run_scope_cmd "$scope" mkdir -p "$(dirname "$unit_path")" >/dev/null 2>&1 || true

    if [ "$scope" = "system" ]; then
        tgdb_warn "此單元屬於 rootful/system scope，將以 sudoedit 開啟。"
        if command -v sudoedit >/dev/null 2>&1; then
            if ! sudoedit "$unit_path"; then
                tgdb_warn "sudoedit 失敗，改以直接開啟編輯器（可能無法儲存）。"
                "$EDITOR" "$unit_path"
            fi
        elif command -v sudo >/dev/null 2>&1; then
            if ! sudo "$EDITOR" "$unit_path"; then
                tgdb_warn "無法透過 sudo 開啟編輯器，改以直接開啟。"
                "$EDITOR" "$unit_path"
            fi
        else
            tgdb_warn "找不到 sudoedit / sudo，改以直接開啟編輯器（可能無法儲存）。"
            "$EDITOR" "$unit_path"
        fi
    else
        "$EDITOR" "$unit_path"
    fi

    local unit_token
    unit_token="$(_podman_token_from_record "$scope" "$fname")"

    _podman_systemctl "$scope" daemon-reload || true
    if _unit_try_enable_now "$unit_token"; then
        _sync_quadlet_unit_to_config "$unit_token"
        echo "✅ 已啟用並送出啟動：$fname（啟動中，可用「查看單元日誌」追蹤）"
    else
        _sync_quadlet_unit_to_config "$unit_token"
        tgdb_warn "已保存，但啟用/啟動可能失敗，請檢查單元內容或日誌。"
    fi
}

_pick_existing_unit_file() {
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    shift || true

    mapfile -t __units < <(_podman_collect_unit_records "$scope" "$@")
    if [ "${#__units[@]}" -eq 0 ]; then
        tgdb_warn "目前沒有任何單元檔可編輯"
        return 1
    fi
    echo "--- 現有單元 ---" >&2
    local i
    local scope name path
    for ((i=0; i<${#__units[@]}; i++)); do
        IFS=$'\t' read -r scope name path <<< "${__units[$i]}"
        printf "%2d) %s\n" $((i+1)) "$(_podman_record_label "$scope" "$name")" >&2
    done
    local pick
    read -r -e -p "請輸入序號或檔名：" pick
    if [ -z "$pick" ]; then
        return 1
    fi
    if [[ "$pick" =~ ^[0-9]+$ ]]; then
        local idx=$((pick-1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#__units[@]} ]; then
            IFS=$'\t' read -r scope name path <<< "${__units[$idx]}"
            printf '%s\n' "$(_podman_token_from_record "$scope" "$name")"
            return 0
        fi
        tgdb_fail "序號超出範圍" 1 || return $?
    fi

    local bare
    bare="$(_podman_token_name "$pick")"
    local rec
    for rec in "${__units[@]}"; do
        IFS=$'\t' read -r scope name path <<< "$rec"
        if [ "$bare" = "$name" ] || [ "$pick" = "$path" ] || [ "$pick" = "$(_podman_token_from_record "$scope" "$name")" ]; then
            printf '%s\n' "$(_podman_token_from_record "$scope" "$name")"
            return 0
        fi
    done

    record="$(_podman_resolve_unit_records "$(_podman_token_from_record "$scope" "$bare")" 2>/dev/null | head -n 1 || true)"
    if [ -n "$record" ]; then
        IFS=$'\t' read -r scope name path <<< "$record"
        printf '%s\n' "$(_podman_token_from_record "$scope" "$name")"
        return 0
    fi

    # 保險：即使找不到，仍以選單 scope 回傳，避免跨 scope 誤操作。
    printf '%s\n' "$(_podman_token_from_record "$scope" "$bare")"
}

_pick_existing_unit_files_multi() {
    local scope
    scope="$(_podman_scope_normalize "${1:-user}")"
    local action_label="$2"
    shift 2

    local -a units=()
    mapfile -t units < <(_podman_collect_unit_records "$scope" "$@")
    if [ "${#units[@]}" -eq 0 ]; then
        tgdb_warn "目前沒有任何單元檔可操作"
        return 1
    fi

    echo "--- 現有單元 ---" >&2
    local i
    local scope name path
    for ((i=0; i<${#units[@]}; i++)); do
        IFS=$'\t' read -r scope name path <<< "${units[$i]}"
        printf "%2d) %s\n" $((i+1)) "$(_podman_record_label "$scope" "$name")" >&2
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
            IFS=$'\t' read -r scope name path <<< "${units[$idx]}"
            resolved="$(_podman_token_from_record "$scope" "$name")"
        else
            local bare
            bare="$(_podman_token_name "$token")"
            resolved=""
            local u
            for u in "${units[@]}"; do
                IFS=$'\t' read -r scope name path <<< "$u"
                if [ "$bare" = "$name" ] || [ "$token" = "$path" ] || [ "$token" = "$(_podman_token_from_record "$scope" "$name")" ]; then
                    resolved="$(_podman_token_from_record "$scope" "$name")"
                    break
                fi
            done
            if [ -z "$resolved" ]; then
                local record
                record="$(_podman_resolve_unit_records "$(_podman_token_from_record "$scope" "$bare")" 2>/dev/null | head -n 1 || true)"
                if [ -n "$record" ]; then
                    IFS=$'\t' read -r scope name path <<< "$record"
                    resolved="$(_podman_token_from_record "$scope" "$name")"
                else
                    tgdb_fail "找不到單元：$token" 1 || return $?
                fi
            fi
        fi

        selected+=("$resolved")
    done

    if [ "$all_selected" = true ]; then
        local rec
        selected=()
        for rec in "${units[@]}"; do
            IFS=$'\t' read -r scope name path <<< "$rec"
            selected+=("$(_podman_token_from_record "$scope" "$name")")
        done
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
    local scope
    scope="$(_podman_unit_scope_from_path "$unit_path")"

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
    local member member_record member_path
    while IFS= read -r member; do
        [ -n "$member" ] || continue
        member_path="$(_podman_unit_path "$scope" "$member")"
        member_record="$(_podman_resolve_unit_records "$(_podman_token_from_record "$scope" "$member")" 2>/dev/null | head -n 1 || true)"
        if [ -n "$member_record" ]; then
            member_path="$(printf '%s\n' "$member_record" | awk -F'\t' 'NF>=3 {print $3; exit}')"
        fi
        service="$(_podman_extract_app_label_from_unit_file "$member_path")"
        if [ -n "$service" ]; then
            printf '%s\n' "$service"
            return 0
        fi
    done < <(_list_pod_member_container_unit_files_by_scope "$scope" "$base" 2>/dev/null || true)

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
    local tgdb_dir_hint="${3:-}"

    _podman_appspec_ensure_exec_loaded || return 0
    _podman_ensure_tgdb_dir || return 0

    local tgdb_dir="${tgdb_dir_hint:-$TGDB_DIR}"
    local instance_dir="$tgdb_dir/$instance"
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
    local tgdb_dir_hint="${3:-}"

    _podman_appspec_ensure_loaded || return 0
    _podman_ensure_tgdb_dir || return 0

    local tgdb_dir="${tgdb_dir_hint:-$TGDB_DIR}"
    local instance_dir="$tgdb_dir/$instance"
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
    if [ -n "$unit_path_hint" ] && [ -f "$unit_path_hint" ]; then
        user_units_dir="$(dirname "$unit_path_hint")"
    else
        user_units_dir="$(_podman_unit_dir user)"
    fi
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
    local tgdb_dir_hint="${4:-}"

    local -A seen=()
    local p

    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -z "${seen[$p]+x}" ]; then
            seen["$p"]=1
            printf '%s\n' "$p"
        fi
    done < <(
        _podman_collect_app_instance_config_paths_from_appspec "$service" "$instance" "$tgdb_dir_hint"
        _podman_collect_app_instance_edit_files_from_appspec "$service" "$instance" "$tgdb_dir_hint"
        _podman_collect_env_files_for_service_instance "$service" "$instance" "$unit_path"
    )
}

_edit_existing_unit_and_reload_restart() {
    local scope_filter
    scope_filter="$(_podman_scope_normalize "${1:-user}")"
    shift || true

    local fname
    fname=$(_pick_existing_unit_file "$scope_filter" container network volume pod device kube) || return 1
    if [ -z "$fname" ]; then tgdb_fail "檔名不可為空" 1 || return $?; fi
    if ! ensure_editor; then
        tgdb_fail "找不到可用的文字編輯器（nano/vim/vi），請先安裝或設定 EDITOR。" 1 || return $?
    fi

    local record scope unit_name unit_path
    record="$(_podman_resolve_unit_records "$fname" 2>/dev/null | head -n 1 || true)"
    if [ -n "$record" ]; then
        IFS=$'\t' read -r scope unit_name unit_path <<< "$record"
    else
        scope="$scope_filter"
        unit_name="$(_podman_token_name "$fname")"
        unit_path="$(_podman_unit_path "$scope_filter" "$unit_name")"
    fi

    local -a edit_files=("$unit_path")
    # Pod 單元通常屬於 multi unit（pod + 多 container），其設定檔可能分散在成員 container/instance 下；
    # 在「編輯 pod 單元」時自動偵測/提示設定檔容易造成誤判與干擾，因此 pod 一律略過設定檔偵測。
    local unit_ext service instance
    unit_ext="${unit_name##*.}"
    service=""
    instance=""
    if [ "$unit_ext" != "pod" ]; then
        service="$(_podman_detect_app_service_for_unit_file "$unit_name" "$unit_path" 2>/dev/null || true)"
        instance="${unit_name%.*}"
        if [ -n "$service" ]; then
            instance="$(_podman_infer_app_instance_from_unit_filename "$service" "$unit_name" 2>/dev/null || echo "$instance")"
        fi

        if [ -n "$service" ] && [ -n "$instance" ]; then
            local -a cfg_files=()
            mapfile -t cfg_files < <(_podman_collect_app_config_paths_for_instance "$service" "$instance" "$unit_path" "$(_podman_runtime_dir_for_scope "$scope")")
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
    fi

    local unit_token
    unit_token="$(_podman_token_from_record "$scope" "$unit_name")"

    if [ "$scope" = "system" ]; then
        tgdb_warn "此單元屬於 rootful/system scope，將以 sudoedit 開啟。"

        # sudoedit 有安全限制：若目標檔案位於「目前使用者可寫入」的目錄，sudoedit 會拒絕開啟。
        # 常見情境：rootful 的 TGDB_ROOTFUL_ROOT 被設成可由一般使用者寫入（或權限配置偏寬），
        # 這時仍希望能順利編輯設定檔，因此自動改用 sudo 直接以 root 身分開啟編輯器。
        local use_sudoedit=0
        if command -v sudoedit >/dev/null 2>&1; then
            use_sudoedit=1
            local f parent
            for f in "${edit_files[@]}"; do
                [ -n "$f" ] || continue
                parent="$(dirname "$f")"
                if [ -d "$parent" ] && [ -w "$parent" ]; then
                    use_sudoedit=0
                    break
                fi
            done
        fi

        if [ "$use_sudoedit" -eq 1 ]; then
            if ! sudoedit "${edit_files[@]}"; then
                tgdb_warn "sudoedit 失敗，將改用 sudo 直接以 root 身分開啟編輯器。"
                if command -v sudo >/dev/null 2>&1; then
                    sudo "$EDITOR" "${edit_files[@]}" || "$EDITOR" "${edit_files[@]}"
                else
                    "$EDITOR" "${edit_files[@]}"
                fi
            fi
        else
            tgdb_warn "偵測到欲編輯的檔案位於目前使用者可寫入的目錄，sudoedit 可能會拒絕；改用 sudo 以 root 身分開啟編輯器。"
            if command -v sudo >/dev/null 2>&1; then
                sudo "$EDITOR" "${edit_files[@]}" || "$EDITOR" "${edit_files[@]}"
            else
                tgdb_warn "找不到 sudo，改以直接開啟編輯器（可能無法儲存）。"
                "$EDITOR" "${edit_files[@]}"
            fi
        fi
    else
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
            if ! _podman_open_editor_with_unshare "${edit_files[@]}"; then
                tgdb_warn "podman unshare 開啟編輯器失敗，將直接開啟編輯器（可能仍無法儲存）。"
                "$EDITOR" "${edit_files[@]}"
            fi
        else
            "$EDITOR" "${edit_files[@]}"
        fi
    fi
    _podman_systemctl "$scope" daemon-reload || true
    _unit_try_enable_now "$unit_token" || true
    if _unit_try_restart "$unit_token"; then
        echo "✅ 已重整並送出重啟：$fname（啟動中，可用「查看單元日誌」追蹤）"
    else
        if _unit_try_enable_now "$unit_token"; then
            echo "✅ 已重整並送出啟動：$fname（啟動中，可用「查看單元日誌」追蹤）"
        else
            tgdb_warn "已保存並重整，但重啟/啟動失敗，請檢查單元或日誌。"
        fi
    fi
}

_podman_open_editor_with_unshare() {
    local tmp_home
    tmp_home="$(mktemp -d "${TMPDIR:-/tmp}/tgdb-unshare-editor.XXXXXX")" || return 1

    mkdir -p \
        "$tmp_home/.config" \
        "$tmp_home/.cache" \
        "$tmp_home/.local/share"

    local rc=0
    if ! env \
        HOME="$tmp_home" \
        XDG_CONFIG_HOME="$tmp_home/.config" \
        XDG_CACHE_HOME="$tmp_home/.cache" \
        XDG_DATA_HOME="$tmp_home/.local/share" \
        podman unshare "$EDITOR" "$@"; then
        rc=$?
    fi

    rm -rf "$tmp_home"
    return "$rc"
}

_remove_quadlet_unit() {
    local token="$1"
    if [ -z "$token" ]; then tgdb_fail "檔名不可為空" 1 || return $?; fi

    local record scope name target_file
    record="$(_podman_resolve_unit_records "$token" 2>/dev/null | head -n 1 || true)"
    if [ -n "$record" ]; then
        IFS=$'\t' read -r scope name target_file <<< "$record"
    else
        scope="$(_podman_token_scope "$token")"
        [ -n "${scope:-}" ] || scope="user"
        scope="$(_podman_scope_normalize "$scope")"
        name="$(_podman_token_name "$token")"
        name="${name%%$'\n'*}"
        target_file="$(_podman_unit_path "$scope" "$name")"
    fi

    if [ ! -e "$target_file" ]; then
        tgdb_warn "找不到單元檔：$target_file"
        return 1
    fi

    local fname base ext
    fname=$(basename "$target_file")
    base="${fname%.*}"
    ext="${fname##*.}"
    local service=""
    service="$(_podman_unit_service_from_path "$target_file" 2>/dev/null || true)"

    if [[ "$ext" = "pod" ]]; then
        local -a members=()
        mapfile -t members < <(_list_pod_member_container_unit_files_by_scope "$scope" "$base")

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
        mapfile -t all_units < <(printf "%s\n" "${all_units[@]}" | awk 'NF && !seen[$0]++' | while IFS= read -r u; do
            [ -n "$u" ] || continue
            if _podman_systemctl "$scope" cat -- "$u" >/dev/null 2>&1; then
                printf '%s\n' "$u"
            fi
        done)
        for u in "${all_units[@]}"; do
            _podman_systemctl "$scope" disable --now -- "$u" >/dev/null 2>&1 || true
        done
        _podman_systemctl "$scope" reset-failed || true

        if command -v podman >/dev/null 2>&1; then
            # 先嘗試移除整個 pod（含 infra/pause），再保險移除成員容器
            _podman_podman_cmd "$scope" pod rm -f "$base" 2>/dev/null || true
            for m in "${members[@]}"; do
                local unit_path
                unit_path="$(_podman_unit_path "$scope" "$m")"
                local member_record=""
                member_record="$(_podman_resolve_unit_records "$(_podman_token_from_record "$scope" "$m")" 2>/dev/null | head -n 1 || true)"
                if [ -n "$member_record" ]; then
                    unit_path="$(printf '%s\n' "$member_record" | awk -F'\t' 'NF>=3 {print $3; exit}')"
                fi
                local cn=""
                cn="$(_container_name_from_unit_file "$unit_path" 2>/dev/null || true)"
                [ -n "$cn" ] || cn="${m%.container}"
                _podman_podman_cmd "$scope" rm -f "$cn" 2>/dev/null || true
            done
        fi

        for m in "${members[@]}"; do
            local member_target=""
            member_target="$(_podman_unit_path "$scope" "$m")"
            local member_record=""
            member_record="$(_podman_resolve_unit_records "$(_podman_token_from_record "$scope" "$m")" 2>/dev/null | head -n 1 || true)"
            if [ -n "$member_record" ]; then
                member_target="$(printf '%s\n' "$member_record" | awk -F'\t' 'NF>=3 {print $3; exit}')"
            fi
            _podman_run_scope_cmd "$scope" rm -f -- "$member_target" 2>/dev/null || true
        done
        _podman_run_scope_cmd "$scope" rm -f -- "$target_file" 2>/dev/null || true
        if [ -n "$service" ] && [ "$target_file" != "$(_podman_unit_path "$scope" "$fname")" ]; then
            local service_dir=""
            service_dir="$(_podman_service_runtime_unit_dir "$scope" "$service" 2>/dev/null || true)"
            if [ -n "$service_dir" ]; then
                if [ "$scope" = "system" ] && ! _podman_is_root; then
                    _podman_run_scope_cmd "$scope" rmdir --ignore-fail-on-non-empty "$service_dir" 2>/dev/null || true
                else
                    rmdir --ignore-fail-on-non-empty "$service_dir" 2>/dev/null || true
                fi
            fi
        fi
        _podman_systemctl "$scope" daemon-reload || true

        local tgdb_dir
        tgdb_dir="$(_podman_runtime_dir_for_scope "$scope")"
        if ui_is_interactive && [ -n "$tgdb_dir" ] && [ -d "$tgdb_dir/$base" ]; then
            if ui_confirm_yn "是否同時刪除實例資料夾（$tgdb_dir/$base）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
                local delete_path="$tgdb_dir/$base"
                if [ "$scope" = "system" ]; then
                    _podman_run_scope_cmd "$scope" rm -rf -- "$delete_path" 2>/dev/null || true
                else
                    podman unshare rm -rf "$delete_path" 2>/dev/null || true
                fi
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
        _podman_systemctl "$scope" disable --now -- "$u" >/dev/null 2>&1 || true
    done < <(_podman_existing_action_units "$scope" "$fname")
    _podman_systemctl "$scope" reset-failed || true

    if [[ "$ext" = "container" ]]; then
        if command -v podman >/dev/null 2>&1; then
            local cn=""
            cn="$(_container_name_from_unit_file "$target_file" 2>/dev/null || true)"
            [ -n "$cn" ] || cn="$base"
            _podman_podman_cmd "$scope" rm -f "$cn" 2>/dev/null || true
        fi
        local tgdb_dir
        tgdb_dir="$(_podman_runtime_dir_for_scope "$scope")"
        if ui_is_interactive; then
            if ui_confirm_yn "是否同時刪除實例資料夾（$tgdb_dir/$base）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
                local delete_path="$tgdb_dir/$base"
                if [ "$scope" = "system" ]; then
                    _podman_run_scope_cmd "$scope" rm -rf -- "$delete_path" 2>/dev/null || true
                else
                    rm -rf "$delete_path" 2>/dev/null || true
                fi
            fi
        else
            tgdb_warn "非互動模式略過刪除實例資料夾：$tgdb_dir/$base"
        fi
    fi

    _podman_run_scope_cmd "$scope" rm -f -- "$target_file" 2>/dev/null || true
    _podman_systemctl "$scope" daemon-reload || true
    echo "✅ 已移除：$fname"
}
