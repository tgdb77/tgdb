spec_version=1
display_name=Activepieces
image=ghcr.io/activepieces/activepieces:latest
doc_url=https://www.activepieces.com/docs/install/options/docker-compose
menu_order=149

base_port=8213
instance_subdirs=cache pgdata rdata
record_subdirs=cache pgdata rdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 activepieces，輸入 0 取消）: |required=1|ask=1|default=activepieces|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=ACTIVEPIECES_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|env=ACTIVEPIECES_DB_PASSWORD|allow_cancel=1

var=ap_encryption_key|source=random_hex|len=32
var=ap_jwt_secret|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=預設使用 `AP_CONTAINER_TYPE=WORKER_AND_APP` 單容器模式搭配 PostgreSQL / Redis，適合單機自架；若之後要把 worker 分離或水平擴充，請依官方文件另外產生 `AP_WORKER_TOKEN` 後再拆分 worker。
success_warn=Webhook / Trigger 要正常被第三方呼叫，`AP_FRONTEND_URL` 必須是外部可達網址；若你目前先用 `http://127.0.0.1:${host_port}`，外部觸發器通常不會正常運作。
success_warn=若之後改成域名 / HTTPS / 反向代理，請編輯 ${instance_dir}/.env 更新 `AP_FRONTEND_URL`，必要時再調整 SMTP、S3 與 SSRF 保護相關設定。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:14-alpine
update_pull_images=docker.io/redis:7-alpine
