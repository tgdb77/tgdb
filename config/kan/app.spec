spec_version=1
display_name=Kan
description=輕量化看板與專案任務管理工具。
image=ghcr.io/kanbn/kan:latest
doc_url=https://github.com/kanbn/kan
menu_order=206

base_port=3998

instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 Kan PostgreSQL 帳號（預設 kan，輸入 0 取消）: |required=1|ask=1|default=kan|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=KAN_DB_USER|allow_cancel=1|cli_zero_as_default=1
input=db_pass|prompt=請輸入 Kan PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=random_hex|len=32|pattern=^[A-Za-z0-9._-]*[A-Za-z][A-Za-z0-9._-]*$|pattern_msg=密碼僅可使用英數、點、底線與連字號，且需包含英文字母。|env=KAN_DB_PASSWORD|allow_cancel=1|cli_zero_as_default=1

var=better_auth_secret|source=random_hex|len=64|env=BETTER_AUTH_SECRET
var=kan_admin_api_key|source=random_hex|len=48|env=KAN_ADMIN_API_KEY
var=email_unsubscribe_secret|source=random_hex|len=48|env=EMAIL_UNSUBSCRIBE_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 Kan Admin API Key：${kan_admin_api_key}
success_warn=預設開啟註冊，首次建立帳號後立即編輯 ${instance_dir}/.env 關閉。
success_warn=若你之後改成反向代理或 HTTPS 網域，請同步更新 ${instance_dir}/.env 的 NEXT_PUBLIC_BASE_URL 與 BETTER_AUTH_TRUSTED_ORIGINS。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=migrate|template=quadlet/default2.container|suffix=-migrate.container
unit=postgres|template=quadlet/default3.container|suffix=-postgres.container

update_pull_images=ghcr.io/kanbn/kan-migrate:latest
update_pull_images=docker.io/library/postgres:16-alpine
