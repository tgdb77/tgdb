spec_version=1
display_name=Formbricks
image=ghcr.io/formbricks/formbricks:latest
doc_url=https://formbricks.com/docs/self-hosting/setup/docker
menu_order=99

base_port=3950

instance_subdirs=saml-connection pgdata valkey_data
record_subdirs=saml-connection pgdata valkey_data

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 formbricks，輸入 0 取消）: |required=1|ask=1|default=formbricks|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=FORMBRICKS_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=FORMBRICKS_DB_PASSWORD|allow_cancel=1

var=nextauth_secret|source=random_hex|len=64|env=FORMBRICKS_NEXTAUTH_SECRET
var=encryption_key|source=random_hex|len=64|env=FORMBRICKS_ENCRYPTION_KEY
var=cron_secret|source=random_hex|len=64|env=FORMBRICKS_CRON_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🌐 WEBAPP_URL / NEXTAUTH_URL：請依實際域名（反向代理/HTTPS）更新 ${instance_dir}/.env。
success_warn= Formbricks 的「檔案上傳/圖片」功能需要設定 S3 相容儲存；未設定時相關功能會被停用（可用外部 S3 或自建 MinIO）。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=valkey|template=quadlet/default3.container|suffix=-valkey.container

update_pull_images=docker.io/pgvector/pgvector:pg17
update_pull_images=docker.io/valkey/valkey:8-alpine

