spec_version=1
display_name=New-Api
image=docker.io/calciumion/new-api:latest
doc_url=https://github.com/QuantumNous/new-api
menu_order=31

base_port=3737
instance_subdirs=pgdata rdata
record_subdirs=pgdata rdata

cli_quick_args=db_user db_pass

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 new_api，輸入 0 取消）: |required=1|ask=1|no_space=1|default=new_api|env=NEW_API_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=NEW_API_DB_PASSWORD|allow_cancel=1

var=session_secret|source=random_hex|len=64
var=crypto_secret|source=random_hex|len=64

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 Redis 密碼：${db_pass}
success_extra=🔁 若使用 Nginx/Cloudflare Tunnel 反向代理，請編輯 ${instance_dir}/.env 的 FRONTEND_BASE_URL（以及需要時的 CORS 相關參數），改成你的公開網址，註釋TLS驗證後重啟單元。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/library/postgres:15-alpine
update_pull_images=docker.io/library/redis:alpine
