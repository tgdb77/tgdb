spec_version=1
display_name=Grav
image=docker.io/getgrav/grav:latest
doc_url=https://github.com/getgrav/docker-grav
menu_order=60

base_port=8099
instance_subdirs=html
record_subdirs=html

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 管理後台：${http_url}/admin
success_warn=Grav 官方映像首次啟動會自動安裝 `grav-admin` 到 ${instance_dir}/html，因此管理後台預設可直接使用；若你之後要改站點網址，請同步調整 Grav 設定或改用反向代理的正式域名。

quadlet_type=single
quadlet_template=quadlet/default.container
