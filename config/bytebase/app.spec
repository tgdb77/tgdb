spec_version=1
display_name=Bytebase
description=管理資料庫變更、審核與版本發布流程。
image=docker.io/bytebase/bytebase:latest
doc_url=https://docs.bytebase.com/get-started/self-host/deploy-with-docker
menu_order=157

base_port=8224
instance_subdirs=data
record_subdirs=data

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 首次啟動後請盡速前往 ${http_url} 完成 setup wizard。
success_warn=若之後改成正式域名 / HTTPS，官方文件建議設定 external URL；你可編輯 ${container_name}.container 加上 `Exec=--external-url https://你的域名` 後重啟。
success_warn=若 Bytebase 要連的是「同一台 Linux 主機上、只監聽 localhost 的資料庫」，建議使用 `--network host` 預設不開，請改用可達的主機 IP/hostname，或自行把 Quadlet 改成 `Network=host`。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/bytebase/bytebase:latest
