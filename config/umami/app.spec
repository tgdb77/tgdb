spec_version=1
display_name=Umami
image=ghcr.io/umami-software/umami:postgresql-latest
doc_url=https://github.com/umami-software/umami
menu_order=32

base_port=3090
instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 umami，輸入 0 取消）: |required=1|ask=1|no_space=1|default=umami|env=UMAMI_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=UMAMI_DB_PASSWORD|allow_cancel=1

var=app_secret|source=random_hex|len=64
var=hash_salt|source=random_hex|len=32

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=👤 預設帳號：admin
success_extra=🔐 預設密碼：umami（登入後請立即更改）
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=ℹ️ 若用 Nginx 反向代理到域名，修改Umami的設定檔BASE_URL/APP_URL更換成自己的域名。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
