#!/bin/bash

# Apps：更新/完全移除（由 src/apps-p.sh 載入）
# 注意：此檔案會被 source，請避免在此更改 shell options（例如 set -euo pipefail）。

_apps_default_volume_dir_path() {
  local service="$1" name="$2"
  local backup_root
  if declare -F tgdb_backup_root >/dev/null 2>&1; then
    backup_root="$(tgdb_backup_root)"
  else
    backup_root="${TGDB_BACKUP_ROOT:-$(dirname "${TGDB_DIR:-$HOME/.tgdb/app}")}"
  fi
  printf '%s\n' "$backup_root/volume/$service/$name"
}

_service_update_and_restart() {
  local service="$1"
  local default_image="${2:-}"
  local forced_instance="${3:-}"
  local forced_image="${4:-}"

  local n image

  if [ -n "$forced_instance" ]; then
    n="$forced_instance"
    if [ -n "$forced_image" ]; then
      image="$forced_image"
    else
      image="$default_image"
    fi
  else
    if ! select_instance "$service" "$default_image"; then
      return
    fi
    n="$SELECTED_INSTANCE"

    if [ -n "$default_image" ]; then
      read -r -e -p "要使用的映像（預設: $default_image）: " image
      image=${image:-$default_image}
    else
      read -r -e -p "要使用的映像（留空則僅重啟，不拉新映像）: " image
    fi
  fi

  echo "您選擇更新實例：$n"

  _app_invoke "$service" update_and_restart_instance "$n" "$image"
  ui_pause "已嘗試更新/重啟，按任意鍵返回..."
}

_full_remove_instance() {
  local service="$1"
  local image="${2:-}"
  local forced_instance="${3:-}"
  local delete_flag="${4:-}"
  local delete_volume_flag="${5:-}"

  local n deld delv="n"
  local default_volume_dir=""
  local volume_dir_guess=""
  local volume_dir_is_default="0"

  if [ -n "$forced_instance" ]; then
    n="$forced_instance"
    # CLI 模式：為了保持與互動 TTY 一致的體驗（預設會刪除資料夾），
    # 這裡採用 0=清理資料夾、1=保留資料夾。
    if [ "$delete_flag" = "0" ]; then
      deld="y"
    else
      deld="n"
    fi

    # 預設不刪除 volume_dir（避免誤刪共用/自訂目錄）
    default_volume_dir="$(_apps_default_volume_dir_path "$service" "$n")"
    if _apps_service_uses_volume_dir "$service" || \
      [ -f "$TGDB_DIR/$n/.tgdb_volume_dir" ] || \
      [ -d "$default_volume_dir" ]; then
      case "${delete_volume_flag:-}" in
        0) delv="n" ;;
        1) delv="y" ;;
        "")
          # 非 CLI、但又是「指定實例」呼叫（例如部分進階工具）：補上互動詢問。
          # - CLI 模式不詢問，避免破壞「一次輸入完全」的設計。
          if ui_is_interactive && [ "${TGDB_CLI_MODE:-0}" != "1" ]; then
            volume_dir_guess="$default_volume_dir"
            if [ -f "$TGDB_DIR/$n/.tgdb_volume_dir" ]; then
              volume_dir_guess="$(head -n 1 "$TGDB_DIR/$n/.tgdb_volume_dir" 2>/dev/null || true)"
              [ -z "$volume_dir_guess" ] && volume_dir_guess="$default_volume_dir"
            fi
            if [ -f "$TGDB_DIR/$n/.tgdb_volume_dir_is_default" ]; then
              volume_dir_is_default="$(head -n 1 "$TGDB_DIR/$n/.tgdb_volume_dir_is_default" 2>/dev/null || echo "0")"
            else
              if [ "$volume_dir_guess" = "$default_volume_dir" ]; then
                volume_dir_is_default="1"
              else
                volume_dir_is_default="0"
              fi
            fi

            local prompt
            if [ "$volume_dir_is_default" = "1" ]; then
              prompt="是否同時刪除 volume_dir（$volume_dir_guess）？(y/N，預設 N，輸入 0 取消): "
            else
              prompt="偵測到 volume_dir 非預設路徑：$volume_dir_guess；是否仍要刪除？(y/N，預設 N，輸入 0 取消): "
            fi

            if ui_confirm_yn "$prompt" "N"; then
              delv="y"
            else
              local vrc=$?
              if [ "$vrc" -eq 2 ]; then
                echo "操作已取消。"
                return
              fi
              delv="n"
            fi
          else
            delv="n"
          fi
          ;;
        *)
          delv="n"
          ;;
      esac
    else
      delv="n"
    fi
  else
    if ! select_instance "$service" "$image"; then
      return
    fi
    n="$SELECTED_INSTANCE"
    if ui_confirm_yn "是否同時刪除實例資料夾（$TGDB_DIR/$n）？(Y/n，預設 Y，輸入 0 取消): " "Y"; then
      deld="y"
    else
      local rc=$?
      if [ "$rc" -eq 2 ]; then
        echo "操作已取消。"
        return
      fi
      deld="n"
    fi

    # 若此服務使用 volume_dir（或偵測到 volume 目錄/metadata），額外詢問是否一併刪除（預設不刪，避免誤刪大量/共用檔案）。
    default_volume_dir="$(_apps_default_volume_dir_path "$service" "$n")"
    if _apps_service_uses_volume_dir "$service" || \
      [ -f "$TGDB_DIR/$n/.tgdb_volume_dir" ] || \
      [ -d "$default_volume_dir" ]; then
      volume_dir_guess="$default_volume_dir"
      if [ -f "$TGDB_DIR/$n/.tgdb_volume_dir" ]; then
        volume_dir_guess="$(head -n 1 "$TGDB_DIR/$n/.tgdb_volume_dir" 2>/dev/null || true)"
        [ -z "$volume_dir_guess" ] && volume_dir_guess="$default_volume_dir"
      fi
      if [ -f "$TGDB_DIR/$n/.tgdb_volume_dir_is_default" ]; then
        volume_dir_is_default="$(head -n 1 "$TGDB_DIR/$n/.tgdb_volume_dir_is_default" 2>/dev/null || echo "0")"
      else
        if [ "$volume_dir_guess" = "$default_volume_dir" ]; then
          volume_dir_is_default="1"
        else
          volume_dir_is_default="0"
        fi
      fi

      local prompt
      if [ "$volume_dir_is_default" = "1" ]; then
        prompt="是否同時刪除 volume_dir（$volume_dir_guess；預設不納入備份）？(y/N，預設 N，輸入 0 取消): "
      else
        prompt="偵測到 volume_dir 非預設路徑：$volume_dir_guess；是否仍要刪除？(y/N，預設 N，輸入 0 取消): "
      fi

      if ui_confirm_yn "$prompt" "N"; then
        delv="y"
      else
        local vrc=$?
        if [ "$vrc" -eq 2 ]; then
          echo "操作已取消。"
          return
        fi
        delv="n"
      fi
    fi
  fi

  echo "您選擇移除實例：$n"

  _app_invoke "$service" full_remove_instance "$n" "$deld" "$delv"
  ui_pause "按任意鍵返回..."
}
