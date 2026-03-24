spec_version=1
display_name=Unbound
image=docker.io/klutchell/unbound:latest
doc_url=https://github.com/NLnetLabs/unbound
menu_order=72

# 注意：DNS 預設埠為 53（特權埠）。
# TGDB 這裡預設以「對外埠」轉發到容器 53（TCP/UDP），避免一定要用 53。
base_port=5333

# 建議僅本機/區網使用；不要將 DNS Resolver 直接暴露到公網。
access_policy=local_only

# 覆寫內建的 forward-records.conf / a-records.conf / srv-records.conf
config=forward-records.conf|template=configs/forward-records.conf.example|mode=644|label=forward-records.conf（上游 DNS / DoT）
config=a-records.conf|template=configs/a-records.conf.example|mode=644|label=a-records.conf（自訂 A/PTR）
config=srv-records.conf|template=configs/srv-records.conf.example|mode=644|label=srv-records.conf（自訂 SRV）

success_extra=ℹ️ 測試指令：dig @127.0.0.1 -p ${host_port} cloudflare.com
success_extra=ℹ️ 進階設定請參考：https://github.com/NLnetLabs/unbound

quadlet_type=single
quadlet_template=quadlet/default.container
