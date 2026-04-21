spec_version=1
display_name=BookStack
image=lscr.io/linuxserver/bookstack:latest
doc_url=https://www.bookstackapp.com/docs/admin/installation/
menu_order=174

base_port=6875
instance_subdirs=config mysql
record_subdirs=config mysql

cli_quick_args=admin_email admin_password db_user db_pass
input=admin_email|prompt=請輸入 BookStack 管理員 Email（預設 admin@example.com，輸入 0 取消）: |required=1|ask=1|default=admin@example.com|no_space=1|pattern=^[^[:space:]@]+@[^[:space:]@]+$|pattern_msg=請輸入有效的 Email。|env=BOOKSTACK_ADMIN_EMAIL|allow_cancel=1
input=admin_password|prompt=請輸入 BookStack 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=24|min_len=8|no_space=1|env=BOOKSTACK_ADMIN_PASSWORD|allow_cancel=1
input=db_user|prompt=請輸入 MariaDB 帳號（預設 bookstack，輸入 0 取消）: |required=1|ask=1|default=bookstack|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 帳號需包含英文字母。|env=DB_USERNAME|allow_cancel=1
input=db_pass|prompt=請輸入 MariaDB 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 密碼需包含英文字母。|disallow=#@:/?|env=DB_PASSWORD|allow_cancel=1

var=mariadb_root_password|source=random_hex|len=32|env=MARIADB_ROOT_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

pre_deploy=scripts/pre_deploy_generate_app_key.sh|runner=bash|allow_fail=0
post_deploy=scripts/post_deploy_create_admin.sh|runner=bash|allow_fail=0

success_extra=🔐 管理員 Email：${admin_email}
success_extra=🔐 管理員密碼：${admin_password}
success_extra=🔐 MariaDB 帳號：${db_user}
success_extra=🔐 MariaDB 密碼：${db_pass}
success_warn= 若你之後改成域名或 HTTPS，請編輯 ${instance_dir}/.env 的 APP_URL，然後執行更新/重啟；若 APP_URL 改變，依官方文件還需執行 URL 更新命令。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=mariadb|template=quadlet/default2.container|suffix=-mariadb.container

update_pull_images=lscr.io/linuxserver/bookstack:latest
update_pull_images=docker.io/library/mariadb:11
