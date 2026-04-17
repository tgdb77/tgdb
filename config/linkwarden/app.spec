spec_version=1
display_name=Linkwarden
image=ghcr.io/linkwarden/linkwarden:latest
doc_url=https://github.com/linkwarden/linkwarden
menu_order=161

base_port=3344
instance_subdirs=data pgdata meili_data
record_subdirs=data pgdata meili_data

cli_quick_args=user_name pass_word
input=user_name|prompt=請輸入 Linkwarden 資料庫帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|env=LINKWARDEN_DB_USER|allow_cancel=1
input=pass_word|prompt=請輸入 Linkwarden 資料庫密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=LINKWARDEN_DB_PASSWORD|allow_cancel=1

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=meilisearch|template=quadlet/default3.container|suffix=-meilisearch.container

update_pull_images=docker.io/postgres:16-alpine
update_pull_images=docker.io/getmeili/meilisearch:v1.12.8
