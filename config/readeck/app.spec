spec_version=1
display_name=Readeck
image=codeberg.org/readeck/readeck:latest
doc_url=https://codeberg.org/readeck/readeck
menu_order=132

base_port=8011

instance_subdirs=data
record_subdirs=data

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 首次啟動後請盡速建立第一個帳號。
success_warn= 若以域名或子路徑反代，請依官方文件調整 Allowed Hosts / Server Prefix / X-Forwarded 設定，避免登入或網址生成異常。

quadlet_type=single
quadlet_template=quadlet/default.container
