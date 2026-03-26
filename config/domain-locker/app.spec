spec_version=1
display_name=Domain Locker
image=docker.io/lissy93/domain-locker:latest
doc_url=https://domain-locker.com/about/self-hosting/deploying-with-docker-compose
menu_order=85

base_port=3455

access_policy=local_only

instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=user_name pass_word
input=user_name|prompt=請輸入 Domain Locker 資料庫帳號（預設 postgres；輸入 0 取消）: |required=1|ask=1|no_space=1|default=postgres|env=DL_PG_USER|allow_cancel=1
input=pass_word|prompt=請輸入 Domain Locker 資料庫密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=DL_PG_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}
success_warn=自架版沒有內建多使用者驗證，強烈建議僅綁定本機並透過反向代理加上驗證與 HTTPS（例如 Nginx + Authentik/Authelia），避免直接暴露到公網。
success_warn=若使用反向代理/域名，請編輯 ${instance_dir}/.env 的 DL_BASE_URL 改成你的正式網址（https://...），再重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=updater|template=quadlet/default3.container|suffix=-updater.container

update_pull_images=docker.io/library/postgres:15-alpine
update_pull_images=docker.io/library/alpine:3.20
