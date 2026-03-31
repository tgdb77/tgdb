spec_version=1
display_name=listmonk
image=docker.io/listmonk/listmonk:latest
doc_url=https://listmonk.app/docs/installation
menu_order=106

base_port=9888

instance_subdirs=pgdata
record_subdirs=pgdata

uses_volume_dir=1
volume_dir_prompt=下載目錄
cli_quick_args=db_user db_pass volume_dir

input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 listmonk，輸入 0 取消）: |required=1|ask=1|default=listmonk|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=FIDER_DB_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 請盡速創建初始用戶。
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=若你之後改成反向代理或 HTTPS 網域，請依官方文件調整外部 URL、代理標頭與公開路徑設定。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:17-alpine
