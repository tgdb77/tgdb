spec_version=1
display_name=Forgejo
image=codeberg.org/forgejo/forgejo:13-rootless
doc_url=https://forgejo.org/docs/latest/admin/installation-docker/
menu_order=133

base_port=3880

instance_subdirs=data conf pgdata
record_subdirs=data conf pgdata

cli_quick_args=db_user db_pass ssh_port
input=db_user|prompt=請輸入 Forgejo PostgreSQL 帳號（預設 forgejo，輸入 0 取消）: |required=1|ask=1|no_space=1|default=forgejo|env=FORGEJO_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Forgejo PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=FORGEJO_DB_PASSWORD|allow_cancel=1
input=ssh_port|prompt=請輸入 Forgejo SSH 對外埠（預設 5226，輸入 0 取消）: |required=1|ask=1|type=port|default_source=next_available_port|start=5226|avoid=host_port|check_available=1|env=FORGEJO_SSH_PORT|allow_cancel=1|cli_zero_as_default=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

edit_files=data/custom/conf/app.ini

success_extra=ℹ️ 首次進入會顯示安裝精靈；資料庫預設已帶入 PostgreSQL，可直接沿用。
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔑 Git over SSH：127.0.0.1:${ssh_port}
success_warn= 若之後改用域名或反向代理，請同步調整 ${instance_dir}/.env 的 FORGEJO__server__ROOT_URL、DOMAIN、SSH_DOMAIN、SSH_PORT。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:14
