spec_version=1
display_name=Odoo
image=docker.io/odoo:latest
doc_url=https://github.com/odoo/docker
menu_order=63

base_port=8166
instance_subdirs=data addons pgdata
record_subdirs=data addons pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 odoo；輸入 0 取消）: |required=1|ask=1|default=odoo|no_space=1|env=ODOO_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=ODOO_DB_PASSWORD|allow_cancel=1
input=master_pass|prompt=請輸入 Odoo 資料庫管理密碼（直接按 Enter 使用隨機密碼）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=ODOO_ADMIN_PASSWD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=odoo.conf|template=configs/odoo.conf.example|mode=600|label=odoo.conf（主設定）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔐 Odoo 資料庫管理密碼：admin_passwd=${master_pass}
success_warn=首次啟動後，請前往 ${http_url}/web/database/manager 建立第一個資料庫，建立時需填入上方的資料庫管理密碼。
success_warn=若之後透過正式域名/HTTPS 對外提供，請登入後將 Odoo 的 `web.base.url` 改成正式網址；若不需要公開資料庫管理頁，建議把 ${instance_dir}/odoo.conf 的 `list_db` 改為 `False` 並設定 `dbfilter`。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:15
