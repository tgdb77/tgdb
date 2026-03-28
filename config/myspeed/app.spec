spec_version=1
display_name=MySpeed
image=docker.io/germannewsmaker/myspeed:latest
doc_url=https://docs.myspeed.dev/setup/linux
menu_order=93

base_port=5211
access_policy=local_only

instance_subdirs=data data/certs data/logs data/servers bin
record_subdirs=data data/certs data/logs data/servers bin

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn= 預設僅綁 127.0.0.1；若要對外提供服務，建議用反向代理（HTTPS）並在 MySpeed 設定頁啟用密碼保護。

quadlet_type=single
quadlet_template=quadlet/default.container

