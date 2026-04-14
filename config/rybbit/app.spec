spec_version=1
display_name=Rybbit
image=ghcr.io/rybbit-io/rybbit-client:latest
doc_url=https://www.rybbit.io/docs/self-hosting-advanced
menu_order=147

base_port=8485
instance_subdirs=nginx pgdata chdata clickhouse/config.d
record_subdirs=nginx pgdata chdata clickhouse/config.d

cli_quick_args=pg_user pg_pass clickhouse_pass
input=pg_user|prompt=請輸入 PostgreSQL 帳號（預設 frog，輸入 0 取消）: |required=1|ask=1|default=frog|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=POSTGRES_USER|allow_cancel=1|cli_zero_as_default=1
input=pg_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=random_hex|len=32|env=POSTGRES_PASSWORD|allow_cancel=1|cli_zero_as_default=1
input=clickhouse_pass|prompt=請輸入 ClickHouse 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=random_hex|len=32|env=CLICKHOUSE_PASSWORD|allow_cancel=1|cli_zero_as_default=1

var=better_auth_secret|source=random_hex|len=64|env=BETTER_AUTH_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=nginx/default.conf|template=configs/nginx/default.conf.example|mode=644|label=Nginx 設定
config=clickhouse/config.d/network.xml|template=configs/clickhouse/config.d/network.xml.example|mode=644|label=ClickHouse network.xml
config=clickhouse/config.d/enable_json.xml|template=configs/clickhouse/config.d/enable_json.xml.example|mode=644|label=ClickHouse enable_json.xml
config=clickhouse/config.d/logging_rules.xml|template=configs/clickhouse/config.d/logging_rules.xml.example|mode=644|label=ClickHouse logging_rules.xml
config=clickhouse/config.d/user_logging.xml|template=configs/clickhouse/config.d/user_logging.xml.example|mode=644|label=ClickHouse user_logging.xml

success_extra=👤 首次請前往 http://127.0.0.1:${host_port}/signup 建立第一個管理員帳號
success_extra=🗄️ PostgreSQL 帳號：${pg_user}
success_extra=🗄️ PostgreSQL 密碼：${pg_pass}
success_extra=🗄️ ClickHouse 帳號：default
success_extra=🗄️ ClickHouse 密碼：${clickhouse_pass}
success_warn= 本範本預設僅綁定 127.0.0.1，且預設允許註冊（DISABLE_SIGNUP=false），方便先建立第一個管理員；建立完成後，建議編輯 ${instance_dir}/.env 將 DISABLE_SIGNUP 改成 true 再重啟。
success_warn= 若要對外公開，建議使用 TGDB 的 Nginx/HTTPS 反代到 127.0.0.1:${host_port}，並把 BASE_URL 改成你的正式 HTTPS 網址。
success_warn= 若要啟用地圖視覺化，請在 .env 補上 MAPBOX_TOKEN。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=nginx|template=quadlet/default.container|suffix=.container
unit=backend|template=quadlet/default2.container|suffix=-backend.container
unit=client|template=quadlet/default3.container|suffix=-client.container
unit=postgres|template=quadlet/default4.container|suffix=-postgres.container
unit=clickhouse|template=quadlet/default5.container|suffix=-clickhouse.container

update_pull_images=ghcr.io/rybbit-io/rybbit-backend:latest
update_pull_images=ghcr.io/rybbit-io/rybbit-client:latest
update_pull_images=docker.io/postgres:17.4
update_pull_images=docker.io/clickhouse/clickhouse-server:25.4.2
update_pull_images=docker.io/library/nginx:stable-alpine
