spec_version=1
display_name=Uptime Kuma
description=服務狀態監控工具，可檢查網站、連線與服務可用性並發送通知。
image=docker.io/louislam/uptime-kuma:2
doc_url=https://github.com/louislam/uptime-kuma
menu_order=17

base_port=3031

config=.env|template=configs/.env.example|mode=600|label=.env

quadlet_type=single
quadlet_template=quadlet/default.container
