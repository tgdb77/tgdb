spec_version=1
display_name=Firefly III
image=docker.io/fireflyiii/core:latest
doc_url=https://github.com/firefly-iii/firefly-iii
menu_order=47

base_port=3434

instance_subdirs=upload pgdata
record_subdirs=upload pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 firefly；輸入 0 取消）: |required=1|ask=1|no_space=1|default=firefly|env=DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=DB_PASS|allow_cancel=1

var=app_key|source=random_hex|len=32
var=static_cron_token|source=random_hex|len=32

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 APP_KEY：${app_key}
success_extra=🔐 STATIC_CRON_TOKEN：${static_cron_token}
success_extra=ℹ️ 上傳檔案目錄：${instance_dir}/upload
success_warn= 反代到域名後，請務必編輯 ${instance_dir}/.env 設定 APP_URL=https://你的域名（必要時一併調整 TRUSTED_PROXIES），並重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=db|template=quadlet/default2.container|suffix=-db.container
unit=cron|template=quadlet/default3.container|suffix=-cron.container

update_pull_images=docker.io/library/postgres:16-alpine
update_pull_images=docker.io/library/alpine:latest
