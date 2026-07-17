headscale_p_menu() {
  _headscale_require_tty || return $?

  while true; do
    clear
    echo "=================================="
    echo "❖ Headscale / DERP（Headscale + Postgres + Headplane）❖"
    echo "=================================="
    echo "教學與文件：https://headscale.net/"
    podman ps --filter label=app=headscale || true
    echo "----------------------------------"
    echo "1. 部署 headscale"
    echo "2. 產生 Headscale API Key"
    echo "3. 更新 Headscale"
    echo "4. Tailscale 管理"
    echo "5. 部署 DERP"
    echo "6. 注入自建 DERP"
    echo "7. 更新 DERP "
    echo "----------------------------------"
    echo "d. 移除應用"
    echo "----------------------------------"
    echo "0. 返回上一層"
    echo "=================================="
    read -r -e -p "請輸入選擇 [0-7/d]: " choice

    case "$choice" in
      1) headscale_p_deploy || true ;;
      2) _headscale_create_ui_apikey_action 0 || true ;;
      3) headscale_p_upgrade_deployed || true ;;
      4)
        _headscale_load_tailscale_module || { ui_pause "按任意鍵返回..."; continue; }
        tailscale_p_menu || true
        ;;
      5)
        _headscale_load_derper_module || { ui_pause "按任意鍵返回..."; continue; }
        derper_p_deploy || true
        ;;
      6)
        _headscale_load_derper_module || { ui_pause "按任意鍵返回..."; continue; }
        derper_p_inject_headscale_detected || true
        ;;
      7)
        _headscale_load_derper_module || { ui_pause "按任意鍵返回..."; continue; }
        derper_p_update_main_program || true
        ;;
      d|D) _headscale_remove_menu || true ;;
      0) return 0 ;;
      *) echo "無效選項，請重新輸入。"; sleep 1 ;;
    esac
  done
}
