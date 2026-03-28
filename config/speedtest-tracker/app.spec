spec_version=1
display_name=Speedtest Tracker
image=lscr.io/linuxserver/speedtest-tracker:latest
doc_url=https://docs.speedtest-tracker.dev
menu_order=95

base_port=3780

instance_subdirs=config pgdata
record_subdirs=config pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 speedtest_tracker，輸入 0 取消）: |required=1|ask=1|no_space=1|default=speedtest_tracker|env=SPEEDTEST_TRACKER_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=SPEEDTEST_TRACKER_DB_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

pre_deploy=scripts/pre_deploy_generate_app_key.sh|runner=bash|allow_fail=0

success_extra=🔐 預設帳號：admin@example.com
success_extra=🔐 預設密碼：password
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn= 請在首次登入後立即修改預設密碼，避免風險。
success_warn= APP_KEY 會由部署流程自動產生並寫入 .env；請勿任意重置，否則可能導致已儲存資料無法解密。
success_warn= 若要透過反向代理（HTTPS）對外提供服務，請務必同步更新 APP_URL（以及信任 Proxy 的相關設定，依官方文件為準）。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
