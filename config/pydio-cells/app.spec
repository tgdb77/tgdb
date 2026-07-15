spec_version=1
display_name=Pydio Cells
description=企業檔案同步、分享與協作平台。
image=docker.io/pydio/cells:latest
doc_url=https://github.com/pydio/cells
menu_order=205

base_port=8091
instance_subdirs=cells mysql initdb
record_subdirs=cells mysql initdb

uses_volume_dir=1
volume_dir_prompt=Pydio Cells 檔案資料目錄
cli_quick_args=db_user db_pass volume_dir

input=db_user|prompt=請輸入 MySQL 帳號（預設 root，輸入 0 取消）: |required=1|ask=1|default=root|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=PYDIO_DB_USER|allow_cancel=1|cli_zero_as_default=1
input=db_pass|prompt=請輸入 MySQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=random_hex|len=32|pattern=^[A-Za-z0-9._-]*[A-Za-z][A-Za-z0-9._-]*$|pattern_msg=MySQL 密碼僅可使用英數、點、底線與連字號，且需包含英文字母。|env=PYDIO_DB_PASSWORD|allow_cancel=1|cli_zero_as_default=1

config=.env|template=configs/.env.example|mode=600|label=.env
config=initdb/01-pydio-user.sql|template=configs/01-pydio-user.sql.example|mode=644|label=MySQL 初始化帳號 SQL

success_extra=🔐 MySQL 帳號：${db_user}
success_extra=🔐 MySQL 密碼：${db_pass}
success_warn=首次開啟 Pydio Cells 時會進入安裝精靈；資料庫請選 MySQL，並填入上方同一 Pod 內的帳號與密碼。
success_warn=預設僅綁定 127.0.0.1:${host_port}，正式對外請搭配 Nginx/HTTPS 反向代理，並在安裝精靈或設定中使用最終外部網址。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=mysql|template=quadlet/default2.container|suffix=-mysql.container

update_pull_images=docker.io/library/mysql:8
