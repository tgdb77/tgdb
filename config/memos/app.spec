spec_version=1
display_name=Memos
image=docker.io/neosmemo/memos:stable
doc_url=https://usememos.com/docs/installation/docker
menu_order=35

base_port=5250

instance_subdirs=pgdata
record_subdirs=pgdata

uses_volume_dir=1
volume_dir_prompt=Memos 資料目錄

cli_quick_args=db_user db_pass volume_dir

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 memos，輸入 0 取消）: |required=1|ask=1|no_space=1|default=memos|env=MEMOS_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=MEMOS_DB_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=ℹ️ 若用 Nginx 反向代理到域名，建議在 ${instance_dir}/.env 設定 MEMOS_INSTANCE_URL=https://你的域名，並重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine

