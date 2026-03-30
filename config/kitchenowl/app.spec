spec_version=1
display_name=KitchenOwl
image=docker.io/tombursch/kitchenowl:latest
doc_url=https://docs.kitchenowl.org/latest/self-hosting/
menu_order=100

base_port=8388

instance_subdirs=data
record_subdirs=data

var=jwt_secret_key|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 若你掛到域名/HTTPS，請編輯 ${instance_dir}/.env 設定 FRONT_URL=https://你的域名 後重啟單元。
success_extra=ℹ️ 請盡速創建初始用戶。

quadlet_type=single
quadlet_template=quadlet/default.container
