spec_version=1
display_name=Claper
image=ghcr.io/claperco/claper:latest
doc_url=https://github.com/ClaperCo/Claper
menu_order=97

base_port=3920

instance_subdirs=uploads pgdata
record_subdirs=uploads pgdata

cli_quick_args=db_user db_pass secret_key_base
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 claper，輸入 0 取消）: |required=1|ask=1|default=claper|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=CLAPER_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=CLAPER_DB_PASSWORD|allow_cancel=1
input=secret_key_base|prompt=請輸入 SECRET_KEY_BASE（直接按 Enter 使用隨機值，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=96|env=CLAPER_SECRET_KEY_BASE|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 SECRET_KEY_BASE：${secret_key_base}
success_warn= 若要透過反向代理（HTTPS）對外提供服務，請同步更新 BASE_URL（以及 Cookie 相關設定）。
success_warn= 如無對外開放註冊需求，建議將 ENABLE_ACCOUNT_CREATION 設為 false。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:15-alpine

