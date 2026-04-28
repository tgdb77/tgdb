spec_version=1
display_name=Lemmy
image=docker.io/dessalines/lemmy:0.19.18
doc_url=https://join-lemmy.org/docs/administration/install_docker.html
menu_order=195

base_port=8882
instance_subdirs=extra_themes pictrs pgdata
record_subdirs=extra_themes pictrs pgdata

cli_quick_args=app_domain db_user db_pass

input=app_domain|prompt=請輸入 Lemmy 最終對外網域（例如 forum.example.com，輸入 0 取消）: |required=1|ask=1|no_space=1|pattern=^[A-Za-z0-9.-]+$|pattern_msg=請只輸入網域名稱，不要包含 http://、https://、路徑或空白。|env=LEMMY_APP_DOMAIN|allow_cancel=1
input=db_user|prompt=請輸入 Lemmy PostgreSQL 帳號（預設 lemmy，輸入 0 取消）: |required=1|ask=1|default=lemmy|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=LEMMY_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Lemmy PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=Lemmy PostgreSQL 密碼需包含英文字母。|disallow=#@:/?|env=LEMMY_DB_PASSWORD|allow_cancel=1

var=pictrs_api_key|source=random_hex|len=32|env=PICTRS_API_KEY

config=.env|template=configs/.env.example|mode=600|label=.env
config=lemmy.hjson|template=configs/lemmy.hjson.example|mode=644|label=lemmy.hjson
config=nginx_internal.conf|template=configs/nginx_internal.conf.example|mode=600|label=nginx_internal.conf
config=proxy_params|template=configs/proxy_params.example|mode=600|label=proxy_params

pre_deploy=scripts/pre_deploy_fix_pictrs_owner.sh|runner=bash|allow_fail=0

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=本範本預設未設定 SMTP；若你需要密碼重設 / 通知郵件，請先編輯 `${instance_dir}/lemmy.hjson` 補上 `email` 區塊後再重啟。
success_warn=若 Federation 不正常，請優先檢查外部反代是否保留 WebSocket 升級標頭，並確認 `https://${app_domain}/.well-known/webfinger`、`/u/<user>`、`/c/<community>` 都可由公網存取。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=proxy|template=quadlet/default.container|suffix=.container
unit=lemmy|template=quadlet/default2.container|suffix=-lemmy.container
unit=ui|template=quadlet/default3.container|suffix=-ui.container
unit=pictrs|template=quadlet/default4.container|suffix=-pictrs.container
unit=postgres|template=quadlet/default5.container|suffix=-postgres.container

update_pull_images=docker.io/nginx:1-alpine
update_pull_images=docker.io/dessalines/lemmy-ui:0.19.18
update_pull_images=docker.io/asonix/pictrs:0.5.23
update_pull_images=docker.io/postgres:18-alpine
