spec_version=1
display_name=Mautic
image=docker.io/mautic/mautic:latest
doc_url=https://github.com/mautic/docker-mautic
menu_order=189

base_port=8068
instance_subdirs=config logs mysql
record_subdirs=config logs mysql

uses_volume_dir=1
volume_dir_prompt=Mautic 媒體資料目錄
volume_subdirs=files images
cli_quick_args=db_user db_pass volume_dir

input=db_user|prompt=請輸入 Mautic MySQL 帳號（預設 mautic，輸入 0 取消）: |required=1|ask=1|default=mautic|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MySQL 帳號需包含英文字母。|env=MAUTIC_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Mautic MySQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MySQL 密碼需包含英文字母。|disallow=#@:/?|env=MAUTIC_DB_PASSWORD|allow_cancel=1

var=mysql_root_password|source=random_hex|len=32|env=MYSQL_ROOT_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 MySQL 帳號：${db_user}
success_extra=🔐 MySQL 密碼：${db_pass}
success_extra=ℹ️ 首次啟動後請盡速完成 Mautic 安裝精靈設定。
success_warn=首次安裝完成前，cron / worker 容器可能會在日誌中看到尚未初始化的錯誤；完成安裝後重新啟動一次通常即可恢復。
success_warn=若之後要改成正式域名或 HTTPS 反代，請依官方文件調整 Mautic 站點 URL 與反向代理設定，避免登入、連結與追蹤網址異常。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=web|template=quadlet/default.container|suffix=.container
unit=mysql|template=quadlet/default2.container|suffix=-mysql.container
unit=cron|template=quadlet/default3.container|suffix=-cron.container
unit=worker|template=quadlet/default4.container|suffix=-worker.container

update_pull_images=docker.io/mautic/mautic:latest
update_pull_images=docker.io/library/mysql:lts
