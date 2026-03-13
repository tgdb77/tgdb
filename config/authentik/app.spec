spec_version=1
display_name=Authentik
image=ghcr.io/goauthentik/server:2025.10.3
doc_url=https://github.com/goauthentik/authentik
menu_order=20

base_port=9988
instance_subdirs=media pgdata
record_subdirs=media pgdata

cli_quick_args=user_name pass_word
input=user_name|prompt=請輸入 Authentik 資料庫帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|env=AUTHENTIK_POSTGRESQL__USER|allow_cancel=1
input=pass_word|prompt=請輸入 Authentik 資料庫密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=AUTHENTIK_POSTGRESQL__PASSWORD|allow_cancel=1

var=secret_key|source=random_hex|len=64|env=AUTHENTIK_SECRET_KEY

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}
success_extra=ℹ️ 初始化：請訪問 ${http_url}/if/flow/initial-setup/ 完成初始設定（正式上線建議使用 Nginx 反代與 HTTPS）。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=worker|template=quadlet/default3.container|suffix=-worker.container

update_pull_images=docker.io/postgres:16-alpine
