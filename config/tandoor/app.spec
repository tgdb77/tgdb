spec_version=1
display_name=Tandoor Recipes
image=docker.io/vabene1111/recipes:latest
doc_url=https://docs.tandoor.dev/install/docker/
menu_order=172

base_port=8081
instance_subdirs=staticfiles mediafiles pgdata
record_subdirs=staticfiles mediafiles pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 tandoor，輸入 0 取消）: |required=1|ask=1|default=tandoor|no_space=1|env=POSTGRES_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=32|env=POSTGRES_PASSWORD|allow_cancel=1

var=secret_key|source=random_hex|len=64|env=SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 盡速創建初始管理員帳號。
success_warn= 若以域名或 HTTPS 反代，請編輯 ${instance_dir}/.env 的 ALLOWED_HOSTS / CSRF_TRUSTED_ORIGINS / ALLAUTH_TRUSTED_PROXY_COUNT 等設定。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
