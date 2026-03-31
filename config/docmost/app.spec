spec_version=1
display_name=Docmost
image=docker.io/docmost/docmost:latest
doc_url=https://docmost.com/docs/installation
menu_order=105

base_port=3345

instance_subdirs=storage pgdata rdata
record_subdirs=storage pgdata rdata

cli_quick_args=db_user db_pass

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 docmost，輸入 0 取消）: |required=1|ask=1|default=docmost|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=FIDER_DB_PASSWORD|allow_cancel=1

var=app_secret|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 請盡速創建初始用戶。
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=若你之後改成反向代理或 HTTPS 網域，請務必同步更新 ${instance_dir}/.env 內的 APP_URL；否則信件連結與部分回呼網址可能不正確。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:18-alpine
update_pull_images=docker.io/redis:8-alpine
