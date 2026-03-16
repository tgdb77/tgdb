spec_version=1
display_name=PostgreSQL
image=docker.io/library/postgres:16-alpine
doc_url=https://github.com/postgres/postgres
menu_order=2

base_port=5432
instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=POSTGRES_PASSWORD

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

input=POSTGRES_DB|prompt=請輸入資料庫名稱（POSTGRES_DB，預設 postgres，輸入 0 取消）: |required=1|no_space=1|default=postgres|env=POSTGRES_DB|allow_cancel=1
input=POSTGRES_USER|prompt=請輸入資料庫帳號（POSTGRES_USER，預設 postgres，輸入 0 取消）: |required=1|no_space=1|default=postgres|env=POSTGRES_USER|allow_cancel=1
input=POSTGRES_PASSWORD|prompt=請輸入資料庫密碼（POSTGRES_PASSWORD，不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=POSTGRES_PASSWORD|allow_cancel=1
input=POSTGRES_INITDB_ARGS|prompt=請輸入 initdb 參數（POSTGRES_INITDB_ARGS，預設 --auth-host=scram-sha-256，輸入 0 取消）: |required=1|no_space=1|default=--auth-host=scram-sha-256|env=POSTGRES_INITDB_ARGS|allow_cancel=1

success_extra=ℹ️ 其他節點要用 tailscale IP 連入：請到「Headscale → Tailnet 服務埠轉發」新增 TCP/${host_port}。
success_extra=ℹ️ 連線字串：postgres://${POSTGRES_USER}:<pass>@<本機tailscaleIP>:${host_port}/${POSTGRES_DB}

quadlet_type=single
quadlet_template=quadlet/default.container
