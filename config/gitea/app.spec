spec_version=1
display_name=Gitea
image=docker.io/gitea/gitea:latest
doc_url=https://docs.gitea.com/installation/install-with-docker
menu_order=36

base_port=3070

instance_subdirs=data pgdata
record_subdirs=data pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 gitea，輸入 0 取消）: |required=1|ask=1|no_space=1|default=gitea|env=GITEA_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=GITEA_DB_PASSWORD|allow_cancel=1

input=ssh_port|prompt=請輸入 Gitea SSH 對外埠: |type=port|ask=1|env=GITEA_SSH_PORT|allow_cancel=1|default_source=next_available_port|start=5225|avoid=host_port

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 首次進入會顯示安裝精靈；經反代後自行填入對應域名。
success_extra=📝 設定檔：${instance_dir}/data/gitea/conf/app.ini
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=🔑 SSH（Git over SSH）對外埠：${ssh_port}/tcp（容器內為 22）
success_extra=🔑 例：git clone ssh://git@你的域名:${ssh_port}/使用者/倉庫.git
success_warn=使用 SSH 功能前請確認已放行 ${ssh_port}/tcp（防火牆/安全群組/NAT 轉發）。
success_warn=若你不需要對外 SSH，建議把 Quadlet 的 SSH PublishPort 改成 127.0.0.1 綁定或註釋掉。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
