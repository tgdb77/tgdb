spec_version=1
display_name=Fider
image=docker.io/getfider/fider:stable
doc_url=https://docs.fider.io/hosting-instance/
menu_order=98

base_port=3930

instance_subdirs=etc pgdata
record_subdirs=etc pgdata

cli_quick_args=db_user db_pass jwt_secret
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 fider，輸入 0 取消）: |required=1|ask=1|default=fider|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=FIDER_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=FIDER_DB_PASSWORD|allow_cancel=1
input=jwt_secret|prompt=請輸入 JWT_SECRET（直接按 Enter 使用隨機值，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=64|env=FIDER_JWT_SECRET|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 JWT_SECRET：${jwt_secret}
success_warn= 若要透過反向代理（HTTPS）對外提供服務，請同步更新 BASE_URL，否則登入信件連結可能不正確。
success_warn= 郵件為必填，需編輯.env透過 SMTP/Mailgun/AWS SES提供註冊服務。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:17
