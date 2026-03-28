spec_version=1
display_name=Kener
image=docker.io/rajnandan1/kener:latest
doc_url=https://github.com/rajnandan1/kener
menu_order=91

base_port=3390

instance_subdirs=pgdata database uploads redis
record_subdirs=pgdata database uploads redis

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 kener；輸入 0 取消）: |required=1|ask=1|no_space=1|default=kener|env=KENER_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼；輸入 0 取消）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=KENER_DB_PASSWORD|allow_cancel=1

var=kener_secret_key|source=random_hex|len=64|env=KENER_SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🖼️ 上傳檔案：${instance_dir}/uploads
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=若透過 Nginx/HTTPS/正式域名提供，請編輯 ${instance_dir}/.env 更新 ORIGIN，並重啟單元。
success_warn=部署成功後請立即建立管理員帳號（避免未設定密碼/權限風險）。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=redis|template=quadlet/default2.container|suffix=-redis.container
unit=postgres|template=quadlet/default3.container|suffix=-postgres.container

update_pull_images=docker.io/redis:7-alpine
update_pull_images=docker.io/postgres:16-alpine
