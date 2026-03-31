spec_version=1
display_name=NocoDB
image=docker.io/nocodb/nocodb:latest
doc_url=https://docs.nocodb.com/
menu_order=108

base_port=8555

instance_subdirs=data pgdata rdata
record_subdirs=data pgdata rdata

cli_quick_args=db_user db_pass

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 nocodb，輸入 0 取消）: |required=1|ask=1|default=nocodb|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|allow_cancel=1|cli_zero_as_default=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=NOCODB_DB_PASSWORD|allow_cancel=1|cli_zero_as_default=1

var=auth_jwt_secret|source=random_hex|len=64|env=NC_AUTH_JWT_SECRET
var=connection_encrypt_key|source=random_hex|len=64|env=NC_CONNECTION_ENCRYPT_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 請盡速創建初始用戶。
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=若要對外提供服務，建議使用 Nginx 反向代理（HTTPS）並設定強密碼；也可在 ${instance_dir}/.env 設定 NC_PUBLIC_URL。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:17-alpine
update_pull_images=docker.io/redis:8-alpine
