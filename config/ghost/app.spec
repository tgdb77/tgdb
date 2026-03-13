spec_version=1
display_name=Ghost
image=docker.io/library/ghost:5-alpine
doc_url=https://github.com/TryGhost/Ghost
menu_order=40

base_port=2377

instance_subdirs=content mysql
record_subdirs=content mysql

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 MySQL 帳號（預設 ghost；輸入 0 取消）: |required=1|ask=1|no_space=1|default=ghost|pattern=.*[A-Za-z].*|pattern_msg=MySQL 帳號需包含英文字母。|env=GHOST_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 MySQL 密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MySQL 密碼需包含英文字母。|disallow=#@:/?|env=GHOST_DB_PASSWORD|allow_cancel=1

var=mysql_root_password|source=random_hex|len=32

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 MySQL 帳號：${db_user}
success_extra=🔐 MySQL 密碼：${db_pass}
success_extra=ℹ️ 初始化：請訪問 ${http_url}/ghost 完成初始設定（正式上線建議使用 Nginx 反代與 HTTPS）。
success_warn= 反代到域名後，請務必編輯 ${instance_dir}/.env 設定 url=https://你的域名（否則連結/資源網址可能不正確），並重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=mysql|template=quadlet/default2.container|suffix=-mysql.container

update_pull_images=docker.io/mysql:8.0
