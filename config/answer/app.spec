spec_version=1
display_name=Apache Answer
image=docker.io/apache/answer:2.0.0
doc_url=https://answer.apache.org/docs/installation
menu_order=156

base_port=8223
instance_subdirs=data pgdata
record_subdirs=data pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 Apache Answer PostgreSQL 帳號（預設 answer，輸入 0 取消）: |required=1|ask=1|default=answer|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=ANSWER_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Apache Answer PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|env=ANSWER_DB_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=ℹ️ 初始化：請訪問 ${http_url}/install 完成初始設定。
success_warn=若之後改成域名 / HTTPS / 子路徑反向代理，請務必同步調整 ${instance_dir}/.env 的 `SITE_URL`；若是子路徑部署，官方文件要求 `SITE_URL` 必須包含完整子路徑。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/apache/answer:2.0.0
update_pull_images=docker.io/postgres:16-alpine
