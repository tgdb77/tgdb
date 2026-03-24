spec_version=1
display_name=Nextcloud
image=docker.io/library/nextcloud:33-apache
doc_url=https://github.com/nextcloud/docker
menu_order=76

base_port=8181
instance_subdirs=html pgdata rdata
record_subdirs=html pgdata rdata

uses_volume_dir=1
volume_dir_prompt=Nextcloud 檔案資料目錄

cli_quick_args=admin_user admin_pass db_user db_pass volume_dir
input=admin_user|prompt=請輸入 Nextcloud 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=NC_ADMIN_USER|allow_cancel=1
input=admin_pass|prompt=請輸入 Nextcloud 管理員密碼（直接按 Enter 使用隨機密碼）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=NC_ADMIN_PASSWORD
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 nextcloud，輸入 0 取消）: |required=1|ask=1|default=nextcloud|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=PostgreSQL 帳號需包含英文字母。|env=NC_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=NC_DB_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 Nextcloud 管理員帳號：${admin_user}
success_extra=🔐 Nextcloud 管理員密碼：${admin_pass}
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 Redis 密碼：${db_pass}
success_warn=⚠️ 反代到正式域名/HTTPS 後，請同步調整 ${instance_dir}/.env 的 NEXTCLOUD_TRUSTED_DOMAINS、TRUSTED_PROXIES、OVERWRITEHOST、OVERWRITEPROTOCOL 與 OVERWRITECLIURL，然後重啟單元。
success_warn=⚠️ 這裡固定使用 docker.io/library/nextcloud:33-apache 以避免未計畫的跨大版升級；升級到新 major 前請先備份 ${instance_dir}。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container
unit=cron|template=quadlet/default4.container|suffix=-cron.container

update_pull_images=docker.io/postgres:16-alpine
update_pull_images=docker.io/redis:7-alpine
