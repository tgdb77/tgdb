#!/bin/bash

# 全系統備份：實例選取、分流與 metadata 處理
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

if [ -n "${_TGDB_BACKUP_INSTANCES_LOADED:-}" ] && [ "${TGDB_FORCE_RELOAD_LIBS:-0}" != "1" ]; then
  return 0
fi
_TGDB_BACKUP_INSTANCES_LOADED=1

_backup_read_meta_value() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 1
    awk -F= -v k="$key" '$1==k { sub(/^[^=]*=/, "", $0); print; exit }' "$file" 2>/dev/null
}

_backup_read_spec_value() {
    local service="$1"
    local key="$2"
    local spec_path="$TGDB_REPO_DIR/config/$service/app.spec"
    [ -f "$spec_path" ] || return 1
    _backup_read_meta_value "$spec_path" "$key"
}

_backup_service_uses_volume_dir() {
    local service="$1"
    local v
    v="$(_backup_read_spec_value "$service" "uses_volume_dir" 2>/dev/null || echo "0")"
    case "${v,,}" in
        1|true|yes|y) return 0 ;;
    esac
    return 1
}

_backup_instance_service_name() {
    local name="$1"
    local meta
    meta="$(_backup_instance_meta_path "$name" 2>/dev/null || true)"
    [ -f "$meta" ] || return 1
    _backup_read_meta_value "$meta" "service"
}

_backup_instance_volume_dir_path() {
    local service="$1"
    local name="$2"
    local meta_path="$TGDB_DIR/$name/.tgdb_volume_dir"
    local volume_dir=""

    if [ -f "$meta_path" ]; then
        volume_dir="$(head -n 1 "$meta_path" 2>/dev/null || true)"
    fi

    if [ -z "${volume_dir:-}" ] || [ "$volume_dir" = "0" ]; then
        volume_dir="$BACKUP_ROOT/volume/$service/$name"
    fi

    printf '%s\n' "$volume_dir"
}

_backup_ensure_volume_dir_subdirs() {
    local service="$1"
    local volume_dir="$2"
    [ -n "${volume_dir:-}" ] || return 0

    local raw
    raw="$(_backup_read_spec_value "$service" "volume_subdirs" 2>/dev/null || true)"
    [ -n "${raw:-}" ] || return 0

    local seg target
    for seg in $raw; do
        [ -n "$seg" ] || continue
        case "$seg" in
            /*|*\\*|*..*)
                tgdb_warn "忽略不合法的 volume_subdirs（$service）：$seg"
                continue
                ;;
        esac
        target="$volume_dir/$seg"
        if ! mkdir -p "$target" 2>/dev/null; then
            podman unshare mkdir -p "$target" 2>/dev/null || {
                tgdb_warn "無法建立 volume_subdirs 目錄：$target"
                return 1
            }
        fi
    done
}

_backup_ensure_restored_instance_volume_dir() {
    local name="$1"
    local service volume_dir

    service="$(_backup_instance_service_name "$name" 2>/dev/null || true)"
    [ -n "${service:-}" ] || return 0
    _backup_service_uses_volume_dir "$service" || return 0

    volume_dir="$(_backup_instance_volume_dir_path "$service" "$name")"
    [ -n "${volume_dir:-}" ] || return 0

    if ! mkdir -p "$volume_dir" 2>/dev/null; then
        podman unshare mkdir -p "$volume_dir" 2>/dev/null || {
            tgdb_warn "無法建立 volume_dir：$volume_dir"
            return 1
        }
    fi

    _backup_ensure_volume_dir_subdirs "$service" "$volume_dir" || return 1
    echo "ℹ️ 已確認 volume_dir：$volume_dir"
    return 0
}

_backup_instance_meta_path() {
    local name="$1"
    [ -n "${name:-}" ] || return 1
    printf '%s\n' "$TGDB_DIR/$name/.tgdb_instance_meta"
}

_backup_instance_name_matches_basename() {
    local base="$1" name="$2"
    [ -n "${base:-}" ] || return 1
    [ -n "${name:-}" ] || return 1
    case "$base" in
        "$name".*|"$name"-*|"$name"__*) return 0 ;;
    esac
    return 1
}

_backup_list_selectable_instances() {
    [ -d "$TGDB_DIR" ] || return 0

    local d meta service name mode
    while IFS= read -r -d $'\0' d; do
        meta="$d/.tgdb_instance_meta"
        [ -f "$meta" ] || continue

        mode="$(_backup_read_meta_value "$meta" "deploy_mode" 2>/dev/null || true)"
        if [ -n "${mode:-}" ] && [ "$mode" != "rootless" ]; then
            continue
        fi

        name="$(_backup_read_meta_value "$meta" "name" 2>/dev/null || true)"
        [ -n "${name:-}" ] || name="$(basename "$d")"
        service="$(_backup_read_meta_value "$meta" "service" 2>/dev/null || true)"
        [ -n "${service:-}" ] || service="unknown"

        printf '%s\t%s\t%s\n' "$name" "$service" "$d"
    done < <(find "$TGDB_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null) | LC_ALL=C sort -t $'\t' -k2,2 -k1,1
}

_backup_parse_multi_selection() {
    local raw="${1:-}"
    local max="${2:-0}"
    BACKUP_SELECTED_INSTANCES=()

    [ -n "${raw:-}" ] || return 1
    [[ "$max" =~ ^[0-9]+$ ]] || return 1

    raw="${raw//,/ }"
    local -a tokens=()
    read -r -a tokens <<< "$raw"

    local -A seen=()
    local token
    for token in "${tokens[@]}"; do
        [ -n "$token" ] || continue
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            if [ "$token" -lt 1 ] || [ "$token" -gt "$max" ]; then
                return 1
            fi
            if [ -z "${seen["$token"]+x}" ]; then
                seen["$token"]=1
                BACKUP_SELECTED_INSTANCES+=("$token")
            fi
            continue
        fi

        if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
            local start="${token%-*}" end="${token#*-}" i
            if [ "$start" -gt "$end" ]; then
                local tmp="$start"
                start="$end"
                end="$tmp"
            fi
            if [ "$start" -lt 1 ] || [ "$end" -gt "$max" ]; then
                return 1
            fi
            for ((i = start; i <= end; i++)); do
                if [ -z "${seen["$i"]+x}" ]; then
                    seen["$i"]=1
                    BACKUP_SELECTED_INSTANCES+=("$i")
                fi
            done
            continue
        fi

        return 1
    done

    [ ${#BACKUP_SELECTED_INSTANCES[@]} -gt 0 ]
}

_backup_pick_instances_interactive() {
    BACKUP_SELECTED_INSTANCES=()

    local -a entries=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && entries+=("$line")
    done < <(_backup_list_selectable_instances)

    if [ ${#entries[@]} -eq 0 ]; then
        tgdb_err "目前找不到可進行指定備份的實例（需位於 $TGDB_DIR，且包含 .tgdb_instance_meta）。"
        return 1
    fi

    echo "----------------------------------"
    echo "可備份實例："
    local i name service dir
    for ((i = 0; i < ${#entries[@]}; i++)); do
        IFS=$'\t' read -r name service dir <<< "${entries[$i]}"
        printf '%2d. %s (%s)\n' "$((i + 1))" "$name" "$service"
    done
    echo "----------------------------------"
    echo "提示：可多選，支援空白 / 逗號 / 範圍，例如：1 3 5-7"

    local pick_raw
    while true; do
        read -r -e -p "請輸入要備份的實例序號（輸入 0 取消）: " pick_raw
        pick_raw="${pick_raw//[$'\t\r\n']/ }"
        pick_raw="${pick_raw#"${pick_raw%%[![:space:]]*}"}"
        pick_raw="${pick_raw%"${pick_raw##*[![:space:]]}"}"
        [ "$pick_raw" = "0" ] && return 1

        if _backup_parse_multi_selection "$pick_raw" "${#entries[@]}"; then
            local -a selected_names=()
            local idx
            for idx in "${BACKUP_SELECTED_INSTANCES[@]}"; do
                IFS=$'\t' read -r name service dir <<< "${entries[$((idx - 1))]}"
                selected_names+=("$name")
            done
            BACKUP_SELECTED_INSTANCES=("${selected_names[@]}")
            return 0
        fi

        tgdb_err "輸入格式不正確，請輸入有效序號、逗號或範圍。"
    done
}

_backup_collect_matching_service_files() {
    local dir="$1"
    local name="$2"
    [ -d "$dir" ] || return 0

    local f base
    while IFS= read -r -d $'\0' f; do
        base="$(basename "$f")"
        if _backup_instance_name_matches_basename "$base" "$name"; then
            printf '%s\n' "$f"
        fi
    done < <(find "$dir" -maxdepth 1 -type f -print0 2>/dev/null)
}

_backup_stage_copy_path() {
    local src="$1"
    local stage_dir="$2"
    local rel="$3"
    [ -e "$src" ] || return 1
    [ -n "${rel:-}" ] || return 1

    mkdir -p "$stage_dir/$(dirname "$rel")" || return 1
    podman unshare cp -a "$src" "$stage_dir/$rel"
}

_backup_stage_selected_instance() {
    local stage_dir="$1"
    local tgdb_name="$2"
    local name="$3"

    local meta instance_dir service
    meta="$(_backup_instance_meta_path "$name" 2>/dev/null || true)"
    [ -f "$meta" ] || {
        tgdb_warn "找不到實例 metadata，略過：$name"
        return 1
    }

    service="$(_backup_read_meta_value "$meta" "service" 2>/dev/null || true)"
    [ -n "${service:-}" ] || {
        tgdb_warn "無法判斷實例所屬服務，略過：$name"
        return 1
    }

    instance_dir="$TGDB_DIR/$name"
    [ -d "$instance_dir" ] || {
        tgdb_warn "找不到實例資料夾，略過：$instance_dir"
        return 1
    }

    _backup_stage_copy_path "$instance_dir" "$stage_dir" "$tgdb_name/$name" || return 1

    local cfg_dir quadlet_dir path rel
    cfg_dir="$(rm_service_configs_dir "$service" 2>/dev/null || true)"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        rel="${path#"$BACKUP_ROOT"/}"
        _backup_stage_copy_path "$path" "$stage_dir" "$rel" || return 1
    done < <(_backup_collect_matching_service_files "$cfg_dir" "$name")

    quadlet_dir="$(rm_service_quadlet_dir "$service" 2>/dev/null || true)"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        rel="${path#"$BACKUP_ROOT"/}"
        _backup_stage_copy_path "$path" "$stage_dir" "$rel" || return 1
    done < <(_backup_collect_matching_service_files "$quadlet_dir" "$name")

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        rel="quadlet/$(basename "$path")"
        _backup_stage_copy_path "$path" "$stage_dir" "$rel" || return 1
    done < <(_backup_collect_matching_service_files "$CONTAINERS_SYSTEMD_DIR" "$name")

    return 0
}

_backup_archive_contains_instance() {
    local archive="$1"
    local name="$2"
    local tgdb_name
    tgdb_name="$(basename "$TGDB_DIR")"

    tar -tzf "$archive" 2>/dev/null | awk -F/ -v app="$tgdb_name" -v target="$name" '
        $1 == app && $2 == target { found=1; exit }
        END { exit(found ? 0 : 1) }
    '
}

_backup_list_select_backup_instance_names() {
    local tgdb_name archive
    tgdb_name="$(basename "$TGDB_DIR")"

    while IFS= read -r archive; do
        [ -n "$archive" ] || continue
        tar -tzf "$archive" 2>/dev/null | awk -F/ -v app="$tgdb_name" '
            $1 == app && NF >= 2 && $2 != "" { print $2 }
        '
    done < <(_backup_list_archives_by_prefix_newest_first "$BACKUP_SELECT_PREFIX") | LC_ALL=C sort -u
}

_backup_get_latest_select_backup_for_instance() {
    local name="$1"
    [ -n "${name:-}" ] || return 1

    local archive
    while IFS= read -r archive; do
        [ -n "$archive" ] || continue
        if _backup_archive_contains_instance "$archive" "$name"; then
            # shellcheck disable=SC2034 # 供還原流程讀取命中的最新指定備份
            LATEST_BACKUP="$archive"
            return 0
        fi
    done < <(_backup_list_archives_by_prefix_newest_first "$BACKUP_SELECT_PREFIX")
    return 1
}

_backup_parse_multi_name_selection() {
    local raw="${1:-}"
    shift || true
    local -a entries=("$@")
    BACKUP_SELECTED_INSTANCES=()

    [ -n "${raw:-}" ] || return 1
    [ ${#entries[@]} -gt 0 ] || return 1

    raw="${raw//,/ }"
    local -a tokens=()
    read -r -a tokens <<< "$raw"
    local -A seen=()
    local token start end idx i

    for token in "${tokens[@]}"; do
        [ -n "$token" ] || continue
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            idx="$token"
            if [ "$idx" -lt 1 ] || [ "$idx" -gt "${#entries[@]}" ]; then
                return 1
            fi
            if [ -z "${seen["$idx"]+x}" ]; then
                seen["$idx"]=1
                BACKUP_SELECTED_INSTANCES+=("${entries[$((idx - 1))]}")
            fi
            continue
        fi

        if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
            start="${token%-*}"
            end="${token#*-}"
            if [ "$start" -gt "$end" ]; then
                i="$start"
                start="$end"
                end="$i"
            fi
            if [ "$start" -lt 1 ] || [ "$end" -gt "${#entries[@]}" ]; then
                return 1
            fi
            for ((i = start; i <= end; i++)); do
                if [ -z "${seen["$i"]+x}" ]; then
                    seen["$i"]=1
                    BACKUP_SELECTED_INSTANCES+=("${entries[$((i - 1))]}")
                fi
            done
            continue
        fi

        return 1
    done

    [ ${#BACKUP_SELECTED_INSTANCES[@]} -gt 0 ]
}
