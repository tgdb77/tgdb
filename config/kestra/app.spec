spec_version=1
display_name=Kestra
image=docker.io/kestra/kestra:latest
doc_url=https://kestra.io/docs/installation/docker-compose
menu_order=158

base_port=8226

instance_subdirs=storage tmp_wd pgdata
record_subdirs=storage tmp_wd pgdata

require_podman_socket=1

cli_quick_args=db_user db_pass 
input=db_user|prompt=請輸入 Kestra PostgreSQL 帳號（預設 kestra，輸入 0 取消）: |required=1|ask=1|default=kestra|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=KESTRA_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Kestra PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|env=KESTRA_DB_PASSWORD|allow_cancel=1

config=application.yml|template=configs/application.yml.example|mode=600|label=application.yml（Kestra 設定）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=ℹ️ 首次啟動後請盡速前往 ${http_url} 完成初始管理員註冊。
success_extra=📁 Kestra 工作目錄：${instance_dir}/tmp_wd
success_warn=若 workflow 需要存取宿主機上只綁 `localhost` 的服務，官方文件建議使用 `host.docker.internal`；TGDB 已在 Pod 內預設加入 `host.docker.internal -> 127.0.0.1` 對應。
success_warn=若之後改成域名 / HTTPS / 反向代理，請務必同步調整 ${instance_dir}/application.yml 內的 `kestra.url`；否則 UI / API 連結可能會指向錯誤位址。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
