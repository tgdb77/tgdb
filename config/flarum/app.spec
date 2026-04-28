spec_version=1
display_name=Flarum
image=docker.io/crazymax/flarum:latest
doc_url=https://github.com/crazy-max/docker-flarum
menu_order=196

base_port=8222
instance_subdirs=data mysql
record_subdirs=data mysql

cli_quick_args=forum_title db_user db_pass
input=forum_title|prompt=請輸入論壇標題（預設 Flarum，輸入 0 取消）: |required=1|ask=1|default=Flarum|env=FLARUM_FORUM_TITLE|allow_cancel=1
input=db_user|prompt=請輸入 MariaDB 帳號（預設 flarum，輸入 0 取消）: |required=1|ask=1|default=flarum|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 帳號需包含英文字母。|env=DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 MariaDB 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 密碼需包含英文字母。|disallow=#@:/?|env=DB_PASSWORD|allow_cancel=1

var=mariadb_root_password|source=random_hex|len=32|env=MARIADB_ROOT_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 預設管理員帳號：flarum
success_extra=🔐 預設管理員密碼：flarum
success_extra=🔐 MariaDB 帳號：${db_user}
success_extra=🔐 MariaDB 密碼：${db_pass}
success_warn= 首次登入後請立即修改 Flarum 預設管理員密碼，並檢查是否要限制註冊與調整權限。
success_warn= 若你之後改成自訂域名或 HTTPS，請編輯 ${instance_dir}/.env 的 FLARUM_BASE_URL 後重新啟動單元，避免登入跳轉或資源網址異常。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=mariadb|template=quadlet/default2.container|suffix=-mariadb.container

update_pull_images=docker.io/crazymax/flarum:latest
update_pull_images=docker.io/mariadb:11
