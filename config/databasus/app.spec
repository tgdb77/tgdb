spec_version=1
display_name=Databasus
image=docker.io/databasus/databasus:latest
doc_url=https://databasus.com/installation
menu_order=172

base_port=4050
instance_subdirs=data
record_subdirs=data

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 首次啟動後請前往 ${http_url} 完成資料庫、儲存目的地與通知設定。
success_warn= 若之後改成域名或 HTTPS 反代，請優先使用 TGDB 的 Nginx/HTTPS 對 127.0.0.1:${host_port} 做反向代理。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/databasus/databasus:latest
