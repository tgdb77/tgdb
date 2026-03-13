spec_version=1
display_name=Ghostfolio
image=docker.io/ghostfolio/ghostfolio:latest
doc_url=https://github.com/ghostfolio/ghostfolio
menu_order=30

base_port=3355
instance_subdirs=pgdata rdata
record_subdirs=pgdata rdata

cli_quick_args=user_name pass_word

input=user_name|prompt=請輸入 Ghostfolio 資料庫帳號（預設 ghostfolio，輸入 0 取消）: |required=1|ask=1|no_space=1|default=ghostfolio|env=GHOSTFOLIO_DB_USER|allow_cancel=1
input=pass_word|prompt=請輸入 Ghostfolio 資料庫密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=GHOSTFOLIO_DB_PASSWORD|allow_cancel=1

var=access_token_salt|source=random_hex|len=32
var=jwt_secret_key|source=random_hex|len=64

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}
success_extra=🔐 Redis 密碼：${pass_word}

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/library/postgres:15-alpine
update_pull_images=docker.io/library/redis:alpine
