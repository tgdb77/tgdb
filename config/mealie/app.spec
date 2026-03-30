spec_version=1
display_name=Mealie
image=ghcr.io/mealie-recipes/mealie:latest
doc_url=https://docs.mealie.io/documentation/getting-started/installation/sqlite/
menu_order=101

base_port=9925

instance_subdirs=data
record_subdirs=data

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 請盡速創建初始用戶。
success_warn= 若用 Nginx 反向代理到域名/HTTPS，請編輯 ${instance_dir}/.env 設定 BASE_URL=https://你的域名 後重啟單元。

quadlet_type=single
quadlet_template=quadlet/default.container
