spec_version=1
display_name=WordPress
image=docker.io/library/wordpress:php8.3-fpm
doc_url=https://github.com/WordPress/WordPress
menu_order=41

base_port=2323

instance_subdirs=html mysql rdata
record_subdirs=html mysql rdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 MySQL 帳號（預設 wordpress；輸入 0 取消）: |required=1|ask=1|no_space=1|default=wordpress|pattern=.*[A-Za-z].*|pattern_msg=MySQL 帳號需包含英文字母。|env=WP_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 MySQL 密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MySQL 密碼需包含英文字母。|disallow=#@:/?|env=WP_DB_PASSWORD|allow_cancel=1

var=mysql_root_password|source=random_hex|len=32

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=nginx.conf|template=configs/nginx.conf.example|mode=644|label=Nginx 設定

success_extra=🔐 MySQL 帳號：${db_user}
success_extra=🔐 MySQL 密碼：${db_pass}
success_warn= 反代到域名後，請到 WordPress 後台把「網站位址（URL）」與「WordPress 位址（URL）」改成你的域名，或在 wp-config.php 設定 WP_HOME/WP_SITEURL，並重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=nginx|template=quadlet/default.container|suffix=.container
unit=fpm|template=quadlet/default2.container|suffix=-fpm.container
unit=mysql|template=quadlet/default3.container|suffix=-mysql.container
unit=redis|template=quadlet/default4.container|suffix=-redis.container

update_pull_images=docker.io/library/nginx:1.27-alpine
update_pull_images=docker.io/library/wordpress:php8.3-fpm
update_pull_images=docker.io/mysql:8.0
update_pull_images=docker.io/redis:7-alpine
