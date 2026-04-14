spec_version=1
display_name=NodeBB
image=ghcr.io/nodebb/nodebb:latest
doc_url=https://docs.nodebb.org/installing/cloud/docker/
menu_order=144

base_port=4568

instance_subdirs=config build uploads pgdata
record_subdirs=config build uploads pgdata

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 nodebb，輸入 0 取消）:|required=1|default=nodebb|ask=1|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=資料庫帳號僅可使用英數、點、底線與連字號。|env=NODEBB_DB_USER
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|env=NODEBB_DB_PASSWORD

config=setup.json|template=configs/setup.json.example|mode=600|label=setup.json

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=若之後改成域名 / HTTPS / 反向代理，請同步調整 ${instance_dir}/config/config.json 內的 `url`，並確認反向代理有正確轉發 WebSocket。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:18.3-alpine
