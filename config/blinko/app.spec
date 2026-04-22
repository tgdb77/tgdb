spec_version=1
display_name=Blinko
image=docker.io/blinkospace/blinko:latest
doc_url=https://github.com/blinkospace/blinko
menu_order=185

base_port=1122

instance_subdirs=app-data pgdata
record_subdirs=app-data pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 postgres，輸入 0 取消）: |required=1|ask=1|default=postgres|no_space=1|env=POSTGRES_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=32|no_space=1|env=POSTGRES_PASSWORD|allow_cancel=1

var=nextauth_secret|source=random_hex|len=64|env=NEXTAUTH_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn= 若之後改成域名或 HTTPS 反代，請編輯 ${instance_dir}/.env 的 NEXTAUTH_URL 與 NEXT_PUBLIC_BASE_URL，避免登入、分享與回呼網址異常。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/blinkospace/blinko:latest
update_pull_images=docker.io/postgres:14
