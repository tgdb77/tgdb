spec_version=1
display_name=Keycloak
image=quay.io/keycloak/keycloak:latest
doc_url=https://github.com/keycloak/keycloak
menu_order=119

base_port=8086
instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=db_user db_pass admin_user admin_pass

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 keycloak；輸入 0 取消）: |required=1|ask=1|no_space=1|default=keycloak|env=KC_DB_USERNAME|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=KC_DB_PASSWORD|allow_cancel=1

input=admin_user|prompt=請輸入 Keycloak 初始管理員帳號（預設 admin；輸入 0 取消）: |required=1|ask=1|no_space=1|default=admin|env=KC_BOOTSTRAP_ADMIN_USERNAME|allow_cancel=1
input=admin_pass|prompt=請輸入 Keycloak 初始管理員密碼（直接按 Enter 使用強密碼；輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=strong_password|len=20|env=KC_BOOTSTRAP_ADMIN_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 Keycloak 初始管理員帳號：${admin_user}
success_extra=🔐 Keycloak 初始管理員密碼：${admin_pass}
success_warn=若要對外提供走 Nginx/HTTPS 反代，編輯 ${instance_dir}/.env 設定相關參數並修改 quadlet：Exec=start。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:17-alpine
