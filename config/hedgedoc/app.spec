spec_version=1
display_name=HedgeDoc
image=quay.io/hedgedoc/hedgedoc:1.10.3
doc_url=https://docs.hedgedoc.org/setup/docker/
menu_order=165

base_port=3461

instance_subdirs=pgdata uploads
record_subdirs=pgdata uploads

cli_quick_args=db_user db_pass

input=db_user|prompt=請輸入 HedgeDoc PostgreSQL 帳號（預設 hedgedoc，輸入 0 取消）: |required=1|ask=1|default=hedgedoc|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=POSTGRES_USER|allow_cancel=1|cli_zero_as_default=1
input=db_pass|prompt=請輸入 HedgeDoc PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=random_hex|len=32|env=POSTGRES_PASSWORD|allow_cancel=1|cli_zero_as_default=1

var=SESSION_SECRET|source=random_hex|len=64|env=CMD_SESSION_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=ℹ️ 首次啟動後請盡速建立第一個帳號；若不再需要開放註冊，可把 ${instance_dir}/.env 內的 CMD_ALLOW_EMAIL_REGISTER 改為 false。
success_warn= 若要透過自訂域名、HTTPS、VSCode Port Forwarding 或非預設埠存取，請編輯 ${instance_dir}/.env 調整 CMD_DOMAIN、CMD_PORT、CMD_URL_ADDPORT、CMD_PROTOCOL_USESSL 與 CMD_ALLOW_ORIGIN，避免登入、分享連結或前端資源網址異常。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
