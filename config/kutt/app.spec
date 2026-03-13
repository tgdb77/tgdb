spec_version=1
display_name=Kutt
image=docker.io/kutt/kutt:latest
doc_url=https://github.com/thedevs-network/kutt
menu_order=33

base_port=3060
instance_subdirs=pgdata rdata custom
record_subdirs=pgdata rdata custom

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 Kutt 資料庫帳號（預設 kutt，輸入 0 取消）: |required=1|ask=1|no_space=1|default=kutt|env=KUTT_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Kutt 資料庫密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=KUTT_DB_PASSWORD|allow_cancel=1

var=jwt_secret|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 Redis 密碼：${db_pass}
success_extra=ℹ️ 若用 Nginx 反向代理到域名，請編輯 ${instance_dir}/.env 的 DEFAULT_DOMAIN 與 TRUST_PROXY，改成你的公開網址後重啟。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:16-alpine
update_pull_images=docker.io/redis:7-alpine
