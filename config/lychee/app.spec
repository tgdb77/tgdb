spec_version=1
display_name=Lychee
image=ghcr.io/lycheeorg/lychee:latest
doc_url=https://github.com/LycheeOrg/Lychee
menu_order=187

base_port=2325
instance_subdirs=logs tmp mysql redis
record_subdirs=logs tmp mysql redis

uses_volume_dir=1
volume_dir_prompt=Lychee 相片資料目錄
volume_subdirs=uploads
cli_quick_args=volume_dir db_user db_pass 

input=db_user|prompt=請輸入 MariaDB 帳號（預設 lychee，輸入 0 取消）: |required=1|ask=1|default=lychee|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 帳號需包含英文字母。|env=DB_USERNAME|allow_cancel=1
input=db_pass|prompt=請輸入 MariaDB 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 密碼需包含英文字母。|disallow=#@:/?|env=DB_PASSWORD|allow_cancel=1

var=db_root_password|source=random_hex|len=32|env=DB_ROOT_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env
pre_deploy=scripts/pre_deploy_generate_app_key.sh|runner=bash|allow_fail=0

success_extra=🔐 MariaDB 帳號：${db_user}
success_extra=🔐 MariaDB 密碼：${db_pass}
success_extra=ℹ️ 首次啟動後請盡速完成初始化與登入。
success_extra=ℹ️ APP_KEY 會寫入 .env ，有需要自行查看。
success_warn= 若你之後改成域名或 HTTPS 反代，請調整 ${instance_dir}/.env 的 APP_URL 與 TRUSTED_PROXIES 等設定（依官方文件），避免分享連結、登入與反代行為異常。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=worker|template=quadlet/default3.container|suffix=-worker.container
unit=redis|template=quadlet/default4.container|suffix=-redis.container
unit=mariadb|template=quadlet/default2.container|suffix=-mariadb.container

update_pull_images=ghcr.io/lycheeorg/lychee:latest
update_pull_images=docker.io/mariadb:10
update_pull_images=docker.io/redis:alpine
