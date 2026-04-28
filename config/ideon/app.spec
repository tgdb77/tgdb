spec_version=1
display_name=Ideon
image=ghcr.io/3xpyth0n/ideon:latest
doc_url=https://github.com/3xpyth0n/ideon
menu_order=198

base_port=3116

instance_subdirs=storage pgdata
record_subdirs=storage pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 ideon，輸入 0 取消）: |required=1|ask=1|default=ideon|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=資料庫帳號僅可使用英數、點、底線與連字號。|env=DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=32|no_space=1|env=DB_PASS|allow_cancel=1

var=secret_key|source=random_hex|len=64|env=SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=ℹ️ 首次啟動後請盡速註冊第一個使用者。
success_warn= 若你之後改成自訂域名或 HTTPS，請編輯 ${instance_dir}/.env 的 APP_URL 後重新啟動單元，避免邀請連結或 SSO 回呼異常。
success_warn= SECRET_KEY 會影響登入 Session 與安全衍生金鑰；部署後請妥善保存，不要隨意更換。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=ghcr.io/3xpyth0n/ideon:latest
update_pull_images=docker.io/postgres:18-alpine
