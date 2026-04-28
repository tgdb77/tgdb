spec_version=1
display_name=PeerTube
image=docker.io/chocobozzz/peertube:production
doc_url=https://docs.joinpeertube.org/install/docker
menu_order=194

base_port=9091
instance_subdirs=config pgdata rdata
record_subdirs=config pgdata rdata

uses_volume_dir=1
volume_dir_prompt=PeerTube 影片資料目錄
cli_quick_args=app_domain admin_email admin_pass db_user db_pass volume_dir


input=app_domain|prompt=請輸入 PeerTube 最終對外網域（例如 video.example.com，輸入 0 取消）: |required=1|ask=1|no_space=1|pattern=^[A-Za-z0-9.-:]+$|pattern_msg=請只輸入網域名稱，不要包含 http://、https://、路徑或空白。|env=PEERTUBE_APP_DOMAIN|allow_cancel=1
input=site_name|prompt=請輸入 PeerTube 站點名稱（預設 PeerTube，輸入 0 取消）: |required=1|ask=1|default=PeerTube|pattern=^[^\"]+$|pattern_msg=站點名稱不可包含雙引號。|env=PEERTUBE_SITE_NAME|allow_cancel=1
input=admin_email|prompt=請輸入 PeerTube 管理員 Email（例如 admin@example.com，輸入 0 取消）: |required=1|ask=1|no_space=1|pattern=^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$|pattern_msg=Email 格式不正確。|env=PEERTUBE_ADMIN_EMAIL|allow_cancel=1
input=admin_pass|prompt=請輸入 PeerTube root 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=20|no_space=1|env=PT_INITIAL_ROOT_PASSWORD|allow_cancel=1
input=db_user|prompt=請輸入 PeerTube PostgreSQL 帳號（預設 peertube，輸入 0 取消）: |required=1|ask=1|default=peertube|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=PEERTUBE_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PeerTube PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=PeerTube PostgreSQL 密碼需包含英文字母。|disallow=#@:/?|env=PEERTUBE_DB_PASSWORD|allow_cancel=1

var=peertube_secret|source=random_hex|len=64|env=PEERTUBE_SECRET
var=redis_pass|source=random_hex|len=32|env=PEERTUBE_REDIS_AUTH

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 PeerTube 管理員帳號：root
success_extra=🔐 PeerTube 管理員密碼：${admin_pass}
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 Redis 密碼：${redis_pass}
success_warn=PeerTube 的網域初始化後不建議頻繁更動；正式對外前請先完成 Nginx/HTTPS 反向代理。
success_warn=預設 `PEERTUBE_SIGNUP_ENABLED=false`、`PEERTUBE_CONTACT_FORM_ENABLED=false`、SMTP 未完成設定；若要開放註冊、聯絡表單或通知信，請先編輯 `${instance_dir}/.env` 後再重啟。
success_warn=直播 RTMP 預設關閉；若你要啟用直播，除了調整 `.env`，還需要額外在 Pod 開放 `1935/tcp`。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/library/postgres:17-alpine
update_pull_images=docker.io/library/redis:8-alpine
