spec_version=1
display_name=Outline
image=docker.io/outlinewiki/outline:latest
doc_url=https://docs.getoutline.com/s/hosting
menu_order=18

base_port=3030
instance_subdirs=app-data pgdata rdata
record_subdirs=app-data pgdata rdata

cli_quick_args=user_name pass_word

input=user_name|prompt=請輸入 Outline 資料庫帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|env=OUTLINE_DB_USER|allow_cancel=1
input=pass_word|prompt=請輸入 Outline 資料庫密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=OUTLINE_DB_PASSWORD|allow_cancel=1

var=secret_key|source=random_hex|len=64|env=OUTLINE_SECRET_KEY
var=utils_secret|source=random_hex|len=64|env=OUTLINE_UTILS_SECRET

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}
success_extra=ℹ️ Outline 需要設定至少一種登入提供者（Slack/Google/Microsoft/Discord/OIDC）才能登入，請編輯 ${instance_dir}/.env 補齊相關參數。
success_extra=ℹ️ 反代完成後，請將 URL/COLLABORATION_URL 改為你的域名（HTTPS/wss）。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:16-alpine
update_pull_images=docker.io/redis:7-alpine
