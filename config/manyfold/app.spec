spec_version=1
display_name=Manyfold
image=ghcr.io/manyfold3d/manyfold:latest
doc_url=https://manyfold.app/get-started/docker
menu_order=81

base_port=3244

instance_subdirs=pgdata rdata
record_subdirs=pgdata rdata

uses_volume_dir=1
volume_dir_prompt=模型庫目錄

cli_quick_args=volume_dir db_user db_pass

input=db_user|prompt=請輸入 Manyfold 資料庫帳號（預設 manyfold，輸入 0 取消）: |required=1|ask=1|default=manyfold|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=MANYFOLD_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 Manyfold 資料庫密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=MANYFOLD_DB_PASSWORD|allow_cancel=1

var=secret_key_base|source=random_hex|len=128

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=📁 模型庫掛載：在「新增 Library」時請填容器內路徑，例如 /libraries/tabletop

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:15-alpine
update_pull_images=docker.io/redis:7-alpine
