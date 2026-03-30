spec_version=1
display_name=LibreDesk
image=docker.io/libredesk/libredesk:latest
doc_url=https://docs.libredesk.io/getting-started/installation
menu_order=104

base_port=9876

instance_subdirs=uploads pgdata rdata
record_subdirs=uploads pgdata rdata

cli_quick_args=db_user db_pass system_pass

input=db_user|prompt=請輸入 LibreDesk PostgreSQL 帳號（預設 libredesk，輸入 0 取消）: |required=1|ask=1|default=libredesk|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=LIBREDESK_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 LibreDesk PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=LIBREDESK_DB_PASSWORD|allow_cancel=1
input=system_pass|prompt=請輸入 System 帳號初始密碼（需含大小寫/數字/特殊字元；直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=strong_password|len=20|min_len=10|max_len=72|require_upper=1|require_lower=1|require_digit=1|require_special=1|env=LIBREDESK_SYSTEM_USER_PASSWORD|allow_cancel=1

var=encryption_key|source=random_hex|len=32

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config.toml|template=configs/config.toml.example|mode=600|label=config.toml

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 初始登入帳號：System
success_extra=🔐 初始登入密碼：${system_pass}

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:17-alpine
update_pull_images=docker.io/redis:7-alpine
