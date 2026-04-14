spec_version=1
display_name=Joplin Server
image=docker.io/joplin/server:latest
doc_url=https://github.com/laurent22/joplin
menu_order=145

base_port=22301

instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 joplin，輸入 0 取消）: |required=1|ask=1|no_space=1|default=joplin|pattern=^[A-Za-z0-9._-]+$|pattern_msg=資料庫帳號僅可使用英數、點、底線與連字號。|env=JOPLIN_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=JOPLIN_DB_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 預設預設帳密： admin@localhost / admin 記得修改。
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=若之後改成域名 / HTTPS / 子路徑反向代理，請同步編輯 ${instance_dir}/.env 的 APP_BASE_URL（例如 https://example.com/joplin）後再重啟單元。
success_warn=目前僅整合 Joplin Server 基本 profile，不含官方 compose 內的 transcribe 額外服務。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16
