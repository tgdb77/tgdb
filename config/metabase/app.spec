spec_version=1
display_name=Metabase
image=docker.io/metabase/metabase:latest
doc_url=https://www.metabase.com/docs/latest/installation-and-operation/running-metabase-on-docker
menu_order=55

base_port=3003
instance_subdirs=config pgdata
record_subdirs=config pgdata

cli_quick_args=user_name pass_word
input=user_name|prompt=請輸入 Metabase 資料庫帳號（預設 metabase；輸入 0 取消）: |required=1|ask=1|no_space=1|default=metabase|env=MB_DB_USER|allow_cancel=1
input=pass_word|prompt=請輸入 Metabase 資料庫密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=MB_DB_PASS|allow_cancel=1

var=mb_encryption_key|source=random_hex|len=64|env=MB_ENCRYPTION_SECRET_KEY

config=config/.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}
success_warn=MB_ENCRYPTION_SECRET_KEY 請勿在上線後任意更換，否則已加密連線資訊可能無法解密。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
