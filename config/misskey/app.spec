spec_version=1
display_name=Misskey
image=localhost/tgdb/misskey:latest
doc_url=https://misskey-hub.net/en/docs/for-admin/install/guides/docker/
menu_order=192

base_port=3006

instance_subdirs=.config files pgdata rdata
record_subdirs=.config files pgdata rdata

cli_quick_args=misskey_url db_user db_pass
input=misskey_url|prompt=請輸入 Misskey 最終對外 URL（例如 https://social.example.com，輸入 0 取消）: |required=1|ask=1|pattern=^https?://.+$|pattern_msg=請輸入完整 URL（需含 http:// 或 https://）。|env=MISSKEY_URL|allow_cancel=1
input=db_user|prompt=請輸入 Misskey PostgreSQL 帳號（預設 misskey，輸入 0 取消）: |required=1|ask=1|default=misskey|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=MISSKEY_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Misskey PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|env=MISSKEY_DB_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env
config=.config/default.yml|template=configs/default.yml.example|mode=600|label=default.yml

pre_build=scripts/pre_build_prepare_source.sh|runner=bash|allow_fail=0
post_build=scripts/post_build_cleanup_source.sh|runner=bash|allow_fail=1

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn= Misskey 的 URL 初始化後不建議再更動；正式對外建議搭配 Nginx 反向代理與 HTTPS。

quadlet_type=multi
unit=build|template=quadlet/default.build|suffix=.build
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:18-alpine
update_pull_images=docker.io/redis:7-alpine
