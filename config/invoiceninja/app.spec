spec_version=1
display_name=Invoice Ninja
image=docker.io/invoiceninja/invoiceninja-debian:latest
doc_url=https://github.com/invoiceninja/dockerfiles
menu_order=90

base_port=2389

instance_subdirs=nginx public storage mysql redis
record_subdirs=nginx public storage mysql redis

cli_quick_args=db_user db_pass admin_email admin_pass
input=db_user|prompt=請輸入 MySQL 帳號（預設 ninja；輸入 0 取消）: |required=1|ask=1|no_space=1|default=ninja|pattern=.*[A-Za-z].*|pattern_msg=MySQL 帳號需包含英文字母。|env=INVOICENINJA_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 MySQL 密碼（直接按 Enter 使用隨機密碼；輸入 0 取消）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|pattern=.*[A-Za-z].*|pattern_msg=MySQL 密碼需包含英文字母。|disallow=#@:/?|env=INVOICENINJA_DB_PASSWORD|allow_cancel=1
input=admin_email|prompt=請輸入 Invoice Ninja 管理員 Email（預設 admin@example.com；輸入 0 取消）: |required=1|ask=1|no_space=1|default=admin@example.com|pattern=^[^[:space:]@]+@[^[:space:]@]+$|pattern_msg=請輸入有效的 Email。|env=INVOICENINJA_ADMIN_EMAIL|allow_cancel=1
input=admin_pass|prompt=請輸入 Invoice Ninja 管理員密碼（直接按 Enter 使用隨機密碼；輸入 0 取消）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|pattern=.*[A-Za-z].*|pattern_msg=管理員密碼需包含英文字母。|disallow=#@:/?|env=INVOICENINJA_ADMIN_PASSWORD|allow_cancel=1

var=mysql_root_password|source=random_hex|len=32

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=nginx/invoiceninja.conf|template=configs/nginx/invoiceninja.conf.example|mode=644|label=Nginx 設定（invoiceninja.conf）
config=nginx/laravel.conf|template=configs/nginx/laravel.conf.example|mode=644|label=Nginx 設定（laravel.conf）

pre_deploy=scripts/pre_deploy_generate_app_key.sh|runner=bash|allow_fail=0

success_extra=🔐 管理員 Email：${admin_email}
success_extra=🔐 管理員密碼：${admin_pass}
success_extra=🔐 MySQL 帳號：${db_user}
success_extra=🔐 MySQL 密碼：${db_pass}
success_warn=反代到域名/HTTPS 後，請編輯 ${instance_dir}/.env 更新 APP_URL 與 REQUIRE_HTTPS，然後重啟單元（否則連結/回呼網址可能不正確）。
success_warn=容器初始化完成後可移除IN_USER_EMAIL和IN_PASSWORD管理員帳密變數。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=nginx|template=quadlet/default.container|suffix=.container
unit=app|template=quadlet/default2.container|suffix=-app.container
unit=mysql|template=quadlet/default3.container|suffix=-mysql.container
unit=redis|template=quadlet/default4.container|suffix=-redis.container

update_pull_images=docker.io/library/nginx:1.27-alpine
update_pull_images=docker.io/mysql:8.0
update_pull_images=docker.io/redis:7-alpine
