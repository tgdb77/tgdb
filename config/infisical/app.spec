spec_version=1
display_name=Infisical
image=docker.io/infisical/infisical:latest
doc_url=https://github.com/Infisical/infisical
menu_order=130

base_port=8082

instance_subdirs=pgdata rdata
record_subdirs=pgdata rdata

cli_quick_args=db_user db_pass auth_secret

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 infisical，輸入 0 取消）: |required=1|ask=1|default=infisical|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=POSTGRES_USER|allow_cancel=1|cli_zero_as_default=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=POSTGRES_PASSWORD|allow_cancel=1|cli_zero_as_default=1
input=auth_secret|prompt=請輸入 Infisical AUTH_SECRET（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=strong_password|len=48|env=AUTH_SECRET|allow_cancel=1|cli_zero_as_default=1

var=encryption_key|source=random_hex|len=32|env=ENCRYPTION_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn= 請在首次啟動後，立刻建立第一個使用者/組織（通常第一位註冊者會成為管理者）。請務必保留 ENCRYPTION_KEY（資料加密相關），遺失可能導致資料無法解密。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:14-alpine
update_pull_images=docker.io/redis:7-alpine

