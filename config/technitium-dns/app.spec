spec_version=1
display_name=Technitium DNS
image=docker.io/technitium/dns-server:latest
doc_url=https://github.com/TechnitiumSoftware/DnsServer
menu_order=74

base_port=5388

access_policy=local_only

instance_subdirs=config
record_subdirs=config

cli_quick_args=tz dns_port server_domain admin_password
input=tz|prompt=請輸入時區 TZ（預設 UTC；輸入 0 取消）: |required=1|ask=1|no_space=1|default=UTC|env=TZ|allow_cancel=1
input=dns_port|prompt=請輸入 DNS 對外埠（預設 53；輸入 0 取消）: |required=1|ask=1|type=port|default=53|check_available=1|allow_cancel=1
input=server_domain|prompt=請輸入 DNS_SERVER_DOMAIN（預設 dns-server；輸入 0 取消）: |required=1|ask=1|no_space=1|default=dns-server|allow_cancel=1
input=admin_password|prompt=請輸入 Web Console 管理密碼（僅允許英文/數字/底線；輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|pattern=^[A-Za-z0-9_]+$|pattern_msg=避免特殊字元造成 .env 解析失敗。|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 Web Console 帳號：admin
success_extra=🔐 Web Console 密碼：${admin_password}
success_extra=ℹ️ 測試 DNS：dig @127.0.0.1 -p ${dns_port} cloudflare.com

quadlet_type=single
quadlet_template=quadlet/default.container
