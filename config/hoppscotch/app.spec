spec_version=1
display_name=Hoppscotch
image=docker.io/hoppscotch/hoppscotch:latest
doc_url=https://docs.hoppscotch.io/documentation/self-host/community-edition/install-and-build
menu_order=137

base_port=3925

instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 Hoppscotch PostgreSQL 帳號（預設 hoppscotch，輸入 0 取消）: |required=1|ask=1|no_space=1|default=hoppscotch|env=HOPPSCOTCH_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Hoppscotch PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=HOPPSCOTCH_DB_PASSWORD|allow_cancel=1

var=data_encryption_key|source=random_hex|len=32|env=DATA_ENCRYPTION_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

post_deploy=scripts/post_deploy_migrate.sh|runner=bash|allow_fail=0

success_extra=🛠️ Admin Dashboard：${http_url}/admin
success_extra=🔌 Backend API：${http_url}/backend/v1
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn= 本範本已啟用官方子路徑模式：App=/、Admin=/admin、Backend=/backend；若你後續改用域名，請同步調整 ${instance_dir}/.env 中的 BASE_URL / BACKEND_URL / WHITELISTED_ORIGINS。
success_warn= 若你要讓桌面版（desktop app）使用，請另外確認 /desktop-app-server 路徑是否已由你的反向代理完整轉發。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
