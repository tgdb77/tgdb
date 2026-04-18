spec_version=1
display_name=wg-easy
image=ghcr.io/wg-easy/wg-easy:15
doc_url=https://github.com/wg-easy/wg-easy
menu_order=169

base_port=31821
instance_subdirs=wireguard
record_subdirs=wireguard

edit_files=wireguard/wg0.json

deploy_mode_default=rootful
compat_deploy_modes=rootful

cli_quick_args=wg_host init_user init_password wg_port
input=wg_host|prompt=請輸入 WireGuard 對外位址（IP 或 FQDN，輸入 0 取消）: |required=1|ask=1|no_space=1|env=INIT_HOST|allow_cancel=1
input=init_user|prompt=請輸入 wg-easy 初始管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=INIT_USERNAME|allow_cancel=1
input=init_password|prompt=請輸入 wg-easy 初始管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=random_hex|min_len=10|len=24|env=INIT_PASSWORD|allow_cancel=1|cli_zero_as_default=1
input=wg_port|prompt=請輸入 WireGuard UDP 對外埠（預設 31820，輸入 0 取消）: |required=1|ask=1|type=port|default=31820|avoid=host_port|check_available=1|env=INIT_PORT|allow_cancel=1|cli_zero_as_default=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 初始管理員帳號：${init_user}
success_extra=🔐 初始管理員密碼：${init_password}
success_extra=🔌 WireGuard UDP：${wg_port}/udp
success_warn= 會把 WireGuard UDP 埠直接監聽在主機所有介面（不是 127.0.0.1）。請先確認防火牆、NAT/路由器轉發與來源控制，再讓客戶端使用。
success_warn= wg-easy 啟動依賴宿主 kernel module 與 sysctl；若隧道無法建立，請依官方 Podman 文件確認宿主已載入 `wireguard`、`ip_tables`、`ip6_tables`、`iptable_nat`、`nft_masq` 等模組。
success_warn= 初始安裝完成後，建議檢查 ${instance_dir}/.env 並視需求移除 `INIT_PASSWORD` 等初始化憑證，避免長期保存明文密碼。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/wg-easy/wg-easy:15
