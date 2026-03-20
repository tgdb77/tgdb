spec_version=1
display_name=ONLYOFFICE
image=docker.io/onlyoffice/documentserver:latest
doc_url=https://github.com/ONLYOFFICE/Docker-DocumentServer
menu_order=65

base_port=8095
instance_subdirs=logs data lib db redis rabbitmq
record_subdirs=logs data lib db redis rabbitmq

var=jwt_secret|source=random_hex|len=32|env=JWT_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 JWT Secret：${jwt_secret}
success_warn=若要整合 Nextcloud / Seafile / Odoo 等外部儲存，請把同一組 JWT_SECRET 與 JWT_HEADER 一起填到對端整合設定；否則文件無法正常開啟或儲存。
success_warn=ONLYOFFICE 預設不支持本地訪問；需透過 Nginx / HTTPS 反向代理後使用，並依需求調整 ALLOW_PRIVATE_IP_ADDRESS、ALLOW_META_IP_ADDRESS。

quadlet_type=single
quadlet_template=quadlet/default.container
