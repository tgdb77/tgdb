spec_version=1
display_name=Paperless-ngx
image=ghcr.io/paperless-ngx/paperless-ngx:latest
doc_url=https://docs.paperless-ngx.com/setup/#docker
menu_order=44

base_port=8686
instance_subdirs=data pgdata rdata
record_subdirs=data pgdata rdata

uses_volume_dir=1
volume_dir_prompt=文件資料目錄
volume_subdirs=media export consume
cli_quick_args=user_name pass_word volume_dir
input=user_name|prompt=請輸入 Paperless PostgreSQL 帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|env=PAPERLESS_DBUSER|allow_cancel=1
input=pass_word|prompt=請輸入 Paperless PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=PAPERLESS_DBPASS|allow_cancel=1

var=secret_key|source=random_hex|len=64|env=PAPERLESS_SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}
success_extra=ℹ️ 投遞文件目錄：${volume_dir}/consume
success_extra=ℹ️ 匯出文件目錄：${volume_dir}/export
success_extra=ℹ️ 若用 Nginx 反向代理到域名，請編輯 ${instance_dir}/.env 的 DPAPERLESS_URL，改成你的公開網址後重啟。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container
unit=gotenberg|template=quadlet/default4.container|suffix=-gotenberg.container
unit=tika|template=quadlet/default5.container|suffix=-tika.container

update_pull_images=docker.io/postgres:16
update_pull_images=docker.io/redis:8
update_pull_images=docker.io/gotenberg/gotenberg:8.25
update_pull_images=ghcr.io/paperless-ngx/tika:latest
