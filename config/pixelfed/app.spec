spec_version=1
display_name=Pixelfed
image=ghcr.io/jippi/docker-pixelfed:v0.12-apache-8.4-bookworm
doc_url=https://jippi.github.io/docker-pixelfed/installation/guide/
menu_order=193

base_port=3463
instance_subdirs=mysql rdata
record_subdirs=mysql rdata

uses_volume_dir=1
volume_dir_prompt=Pixelfed 媒體／快取資料目錄
volume_subdirs=storage cache

cli_quick_args=app_domain db_user db_pass volume_dir

input=app_domain|prompt=請輸入 Pixelfed 最終對外網域（例如 pix.example.com，輸入 0 取消）: |required=1|ask=1|no_space=1|pattern=^[A-Za-z0-9.-]+$|pattern_msg=請只輸入網域名稱，不要包含 http://、https://、路徑或空白。|env=PIXELFED_APP_DOMAIN|allow_cancel=1
input=site_name|prompt=請輸入 Pixelfed 站點名稱（預設 Pixelfed，輸入 0 取消）: |required=1|ask=1|default=Pixelfed|pattern=^[^\"]+$|pattern_msg=站點名稱不可包含雙引號。|env=PIXELFED_SITE_NAME|allow_cancel=1
input=db_user|prompt=請輸入 Pixelfed MariaDB 帳號（預設 pixelfed，輸入 0 取消）: |required=1|ask=1|default=pixelfed|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=PIXELFED_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Pixelfed MariaDB 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=Pixelfed MariaDB 密碼需包含英文字母。|disallow=#@:/?|env=PIXELFED_DB_PASSWORD|allow_cancel=1

var=db_root_pass|source=random_hex|len=32|env=PIXELFED_DB_ROOT_PASSWORD
var=redis_pass|source=random_hex|len=32|env=PIXELFED_REDIS_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 MariaDB 帳號：${db_user}
success_extra=🔐 MariaDB 密碼：${db_pass}
success_extra=🔐 Redis 密碼：${redis_pass}
success_warn=Pixelfed 的 `APP_URL` / `APP_DOMAIN` 建議從一開始就填最終對外網域，部署後不建議頻繁更動。
success_warn=預設 `OPEN_REGISTRATION=false`、`MAIL_DRIVER=log`；若要開放註冊或啟用寄信，請先編輯 `${instance_dir}/.env`，再重啟服務。
success_warn=若要把既有帳號提升為管理員，可在服務啟動完成後執行：`podman exec -it ${container_name} php artisan user:admin <帳號>`

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=web|template=quadlet/default.container|suffix=.container
unit=worker|template=quadlet/default2.container|suffix=-worker.container
unit=cron|template=quadlet/default3.container|suffix=-cron.container
unit=db|template=quadlet/default4.container|suffix=-db.container
unit=redis|template=quadlet/default5.container|suffix=-redis.container

update_pull_images=docker.io/mariadb:11.6
update_pull_images=docker.io/redis:7.4.2
