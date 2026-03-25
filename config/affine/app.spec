spec_version=1
display_name=AFFiNE
image=ghcr.io/toeverything/affine:stable
doc_url=https://github.com/toeverything/AFFiNE
menu_order=80

base_port=3331

instance_subdirs=config storage pgdata rdata
record_subdirs=config storage pgdata rdata

cli_quick_args=db_user db_pass

input=db_user|prompt=請輸入 AFFiNE 資料庫帳號（預設 affine，輸入 0 取消）: |required=1|ask=1|default=affine|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=AFFINE_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 AFFiNE 資料庫密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=AFFINE_DB_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config/config.json|template=configs/config.json.example|mode=600|label=config.json（AFFiNE 設定）

edit_files=/config/config.json

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🧩 進階設定：請視需求編輯 ${instance_dir}/.env 與 ${instance_dir}/config/config.json。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=migration|template=quadlet/default2.container|suffix=-migration.container
unit=postgres|template=quadlet/default3.container|suffix=-postgres.container
unit=redis|template=quadlet/default4.container|suffix=-redis.container

update_pull_images=docker.io/pgvector/pgvector:pg16
update_pull_images=docker.io/redis:7-alpine

