spec_version=1
display_name=Flowise
image=docker.io/flowiseai/flowise:latest
doc_url=https://docs.flowiseai.com/
menu_order=109

base_port=3386
instance_subdirs=flowise pgdata
record_subdirs=flowise pgdata

cli_quick_args=db_user db_pass

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 flowise，輸入 0 取消）: |required=1|ask=1|default=flowise|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=FLOWISE_DB_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 請盡速創建初始用戶。
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=若你用 Nginx 反向代理到正式域名/HTTPS，請記得同步設定 ${instance_dir}/.env 的 APP_URL，然後重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/library/postgres:16-alpine
