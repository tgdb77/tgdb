spec_version=1
display_name=Sub2API
image=docker.io/weishaw/sub2api:latest
doc_url=https://github.com/Wei-Shaw/sub2api
menu_order=159

base_port=8227

instance_subdirs=data pgdata rdata
record_subdirs=data pgdata rdata

cli_quick_args=db_user db_pass admin_email admin_pass
input=db_user|prompt=請輸入 Sub2API PostgreSQL 帳號（預設 sub2api，輸入 0 取消）: |required=1|ask=1|default=sub2api|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=POSTGRES_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Sub2API PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=64|no_space=1|env=POSTGRES_PASSWORD|allow_cancel=1
input=admin_email|prompt=請輸入 Sub2API 管理員 Email（預設 admin@sub2api.local，輸入 0 取消）: |required=1|ask=1|default=admin@sub2api.local|no_space=1|pattern=^[^[:space:]@]+@[^[:space:]@]+$|pattern_msg=請輸入有效的 Email。|env=ADMIN_EMAIL|allow_cancel=1
input=admin_pass|prompt=請輸入 Sub2API 管理員密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=strong_password|min_len=6|len=20|no_space=1|env=ADMIN_PASSWORD|allow_cancel=1

var=jwt_secret|source=random_hex|len=64|env=JWT_SECRET
var=totp_encryption_key|source=random_hex|len=64|env=TOTP_ENCRYPTION_KEY
var=redis_password|source=random_hex|len=64|env=REDIS_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 管理員 Email：${admin_email}
success_extra=🔐 管理員密碼：${admin_pass}
success_warn=若之後要改公開位址或埠號，請同步調整 ${instance_dir}/.env 的 `SERVER_PORT`、反向代理與防火牆設定；若管理員密碼留空則官方會自動生成，但 TGDB 這裡已預設幫你填入一組已知強密碼。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:16-alpine
update_pull_images=docker.io/redis:7-alpine
