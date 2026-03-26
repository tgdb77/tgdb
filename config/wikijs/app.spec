spec_version=1
display_name=Wiki.js
image=docker.io/requarks/wiki:2
doc_url=https://docs.requarks.io/install/docker
menu_order=87

base_port=3457

instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=user_name pass_word
input=user_name|prompt=請輸入 PostgreSQL 帳號（預設 wikijs；輸入 0 取消）: |required=1|ask=1|no_space=1|default=wikijs|env=DB_USER|allow_cancel=1
input=pass_word|prompt=請輸入 PostgreSQL 密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=DB_PASS|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/library/postgres:15-alpine

