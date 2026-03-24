spec_version=1
display_name=Pi-hole
image=docker.io/pihole/pihole:latest
doc_url=https://github.com/pi-hole/docker-pi-hole
menu_order=73

base_port=3899

access_policy=local_only

instance_subdirs=etc-pihole etc-dnsmasq.d
record_subdirs=etc-pihole etc-dnsmasq.d

cli_quick_args=tz dns_port web_password
input=tz|prompt=請輸入時區 TZ（預設 UTC；輸入 0 取消）: |required=1|ask=1|no_space=1|default=UTC|env=TZ|allow_cancel=1
input=dns_port|prompt=請輸入 DNS 對外埠（預設 53；輸入 0 取消）: |required=1|ask=1|type=port|default=53|check_available=1|allow_cancel=1
input=web_password|prompt=請輸入 Web 管理介面密碼（僅允許英文/數字/底線；輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|pattern=^[A-Za-z0-9_]+$|pattern_msg=密碼僅允許英文/數字/底線（避免特殊字元造成 .env 解析失敗）。|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 Web 管理介面密碼：${web_password}
success_extra=ℹ️ Web 管理介面預設僅本機訪問： http://127.0.0.1:${host_port}/admin

quadlet_type=single
quadlet_template=quadlet/default.container
