spec_version=1
display_name=Penpot
image=docker.io/penpotapp/frontend:latest
doc_url=https://github.com/penpot/penpot
menu_order=126

base_port=8002
instance_subdirs=assets pgdata
record_subdirs=assets pgdata

cli_quick_args=user_name pass_word admin_name admin_email admin_password

input=user_name|prompt=請輸入 PostgreSQL 帳號（預設 penpot，輸入 0 取消）: |required=1|ask=1|default=penpot|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=POSTGRES_USER|allow_cancel=1|cli_zero_as_default=1
input=pass_word|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=POSTGRES_PASSWORD|allow_cancel=1|cli_zero_as_default=1
input=admin_name|prompt=請輸入 Penpot 初始管理員名稱（預設 Admin，輸入 0 取消）: |required=1|ask=1|default=Admin|env=PENPOT_ADMIN_NAME|allow_cancel=1|cli_zero_as_default=1
input=admin_email|prompt=請輸入 Penpot 初始管理員 Email（預設 admin@localhost.local，輸入 0 取消）: |required=1|ask=1|default=admin@localhost.local|no_space=1|pattern=^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$|pattern_msg=請輸入有效的 Email。|env=PENPOT_ADMIN_EMAIL|allow_cancel=1|cli_zero_as_default=1
input=admin_password|prompt=請輸入 Penpot 初始管理員密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=strong_password|len=24|env=PENPOT_ADMIN_PASSWORD|allow_cancel=1|cli_zero_as_default=1

var=secret_key|source=random_hex|len=128|env=PENPOT_SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}
success_extra=👤 Penpot 初始管理員名稱：${admin_name}
success_extra=👤 Penpot 初始管理員 Email：${admin_email}
success_extra=👤 Penpot 初始管理員密碼：${admin_password}

success_warn= 預設關閉註冊（disable-registration）。若你要開放註冊，請編輯 ${instance_dir}/.env 調整 PENPOT_FLAGS。
success_warn= 若你要上線到網際網路，請改用 HTTPS（反向代理）並移除 .env 中 disable-secure-session-cookies / disable-email-verification 不安全旗標，並修改 PENPOT_PUBLIC_URI 為你的對外域名。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=frontend|template=quadlet/default.container|suffix=.container
unit=backend|template=quadlet/default2.container|suffix=-backend.container
unit=exporter|template=quadlet/default3.container|suffix=-exporter.container
unit=postgres|template=quadlet/default4.container|suffix=-postgres.container
unit=valkey|template=quadlet/default5.container|suffix=-valkey.container

post_deploy=scripts/post_deploy_create_admin.sh|runner=bash|allow_fail=0

update_pull_images=docker.io/penpotapp/frontend:latest
update_pull_images=docker.io/penpotapp/backend:latest
update_pull_images=docker.io/penpotapp/exporter:latest
update_pull_images=docker.io/postgres:15-alpine
update_pull_images=docker.io/valkey/valkey:8.1-alpine
