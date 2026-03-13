spec_version=1
display_name=Vikunja
image=docker.io/vikunja/vikunja:latest
doc_url=https://github.com/go-vikunja/vikunja
menu_order=48

base_port=3113

instance_subdirs=files pgdata
record_subdirs=files pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 vikunja；輸入 0 取消）: |required=1|ask=1|no_space=1|default=vikunja|env=DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=DB_PASS|allow_cancel=1

var=jwt_secret|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 JWT Secret：${jwt_secret}
success_extra=ℹ️ 檔案目錄：${instance_dir}/files
success_warn=⚠️ 反代到域名後，請務必編輯 ${instance_dir}/.env 設定 VIKUNJA_SERVICE_PUBLICURL=https://你的域名，並重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=db|template=quadlet/default2.container|suffix=-db.container

update_pull_images=docker.io/library/postgres:16-alpine

