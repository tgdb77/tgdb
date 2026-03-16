spec_version=1
display_name=Mumble
image=docker.io/mumblevoip/mumble-server:latest
doc_url=https://github.com/mumble-voip/mumble-docker
menu_order=56

base_port=64738
instance_subdirs=data
record_subdirs=data

input=MUMBLE_SUPERUSER_PASSWORD|prompt=請輸入 SuperUser 密碼（直接按 Enter 使用隨機密碼）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=MUMBLE_SUPERUSER_PASSWORD
input=MUMBLE_CONFIG_SERVERPASSWORD|prompt=請輸入伺服器加入密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=MUMBLE_CONFIG_SERVERPASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 SuperUser 帳號：superuser
success_extra=🔐 SuperUser 密碼：${MUMBLE_SUPERUSER_PASSWORD}
success_extra=🔐 加入密碼：${MUMBLE_CONFIG_SERVERPASSWORD}
success_extra=🎧 Mumble 用戶端連線：${access_host}:${host_port}，前端：https://www.mumble.info/downloads。
success_warn=連線提醒：請確保已放行 ${host_port}/TCP 與 ${host_port}/UDP（防火牆/安全群組/NAT 轉發），不須要反代。
success_warn=安全建議：若不想對外公開，請在自訂 Quadlet 將 PublishPort 改為綁定 127.0.0.1（或搭配 VPN / SSH 轉發）。
success_warn=設定提示：更多 murmur.ini 設定可用環境變數 MUMBLE_CONFIG_<KEY> 調整。

quadlet_type=single
quadlet_template=quadlet/default.container
