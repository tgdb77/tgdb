spec_version=1
display_name=Planka
image=docker.io/plankanban/planka:latest
doc_url=https://github.com/plankanban/planka
menu_order=173

base_port=1330
instance_subdirs=user-avatars project-background-images attachments pgdata rdata
record_subdirs=user-avatars project-background-images attachments pgdata rdata

cli_quick_args=admin_email admin_password db_user db_pass
input=admin_email|prompt=請輸入 Planka 管理員 Email（預設 admin@example.com，輸入 0 取消）: |required=1|ask=1|default=admin@example.com|no_space=1|pattern=^[^[:space:]@]+@[^[:space:]@]+$|pattern_msg=請輸入有效的 Email。|env=DEFAULT_ADMIN_EMAIL|allow_cancel=1
input=admin_password|prompt=請輸入 Planka 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=24|no_space=1|env=DEFAULT_ADMIN_PASSWORD|allow_cancel=1
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 planka，輸入 0 取消）: |required=1|ask=1|default=planka|no_space=1|env=POSTGRES_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=32|no_space=1|env=POSTGRES_PASSWORD|allow_cancel=1

var=secret_key|source=random_hex|len=64|env=SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 管理員 Email：${admin_email}
success_extra=🔐 管理員密碼：${admin_password}
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn= 若你之後改成域名或 HTTPS，請編輯 ${instance_dir}/.env 的 BASE_URL 與 TRUST_PROXY，避免登入跳轉、邀請連結或附件網址異常。
success_warn= 若你要開啟郵件通知、OIDC 或 LDAP，請依官方文件在 ${instance_dir}/.env 補上 SMTP / OIDC / LDAP 相關變數。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:16-alpine
update_pull_images=docker.io/redis:7-alpine
