spec_version=1
display_name=Chatwoot
image=docker.io/chatwoot/chatwoot:latest
doc_url=https://github.com/chatwoot/chatwoot
menu_order=121

base_port=3838
instance_subdirs=storage pgdata redis
record_subdirs=storage pgdata redis

cli_quick_args=db_user db_pass redis_pass

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 chatwoot；輸入 0 取消）: |required=1|ask=1|no_space=1|default=chatwoot|env=CHATWOOT_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=CHATWOOT_DB_PASSWORD|allow_cancel=1
input=redis_pass|prompt=請輸入 Redis 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=CHATWOOT_REDIS_PASSWORD|allow_cancel=1

var=secret_key_base|source=random_hex|len=64|env=SECRET_KEY_BASE

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

# 部署後初始化：嘗試執行 db:chatwoot_prepare（可在 .env 關閉）
post_deploy=scripts/post_deploy_prepare_db.sh|runner=bash|allow_fail=1

success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 Redis 密碼：${redis_pass}
success_warn=首次部署後請執行資料庫初始化（已預設自動嘗試執行）。若失敗，請查看單元日誌或手動在容器內執行：bundle exec rails db:chatwoot_prepare
success_warn=若你想用 UI 註冊第一個管理員：請暫時將 ENABLE_ACCOUNT_SIGNUP=true，註冊完成後再改回 false 並重啟服務。
success_warn=若要對外公開，請用 Nginx/HTTPS 反代，並務必把 FRONTEND_URL 改為你的公開 https 網址後再重啟。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=rails|template=quadlet/default.container|suffix=.container
unit=sidekiq|template=quadlet/default2.container|suffix=-sidekiq.container
unit=postgres|template=quadlet/default3.container|suffix=-postgres.container
unit=redis|template=quadlet/default4.container|suffix=-redis.container

update_pull_images=docker.io/pgvector/pgvector:pg16
update_pull_images=docker.io/redis:alpine
