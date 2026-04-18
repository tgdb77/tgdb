spec_version=1
display_name=MariaDB
image=docker.io/library/mariadb:11
doc_url=https://github.com/MariaDB/mariadb-docker
menu_order=6

access_policy=local_only

base_port=3307
instance_subdirs=mysql
record_subdirs=mysql

cli_quick_args=MARIADB_DATABASE MARIADB_USER MARIADB_PASSWORD MARIADB_ROOT_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

input=MARIADB_DATABASE|prompt=請輸入資料庫名稱（預設 mariadb，輸入 0 取消）: |required=1|no_space=1|ask=1|default=mariadb|env=MARIADB_DATABASE|allow_cancel=1
input=MARIADB_USER|prompt=請輸入資料庫帳號（預設 mariadb，輸入 0 取消）: |required=1|no_space=1|ask=1|default=mariadb|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 帳號需包含英文字母。|env=MARIADB_USER|allow_cancel=1
input=MARIADB_PASSWORD|prompt=請輸入資料庫密碼（MARIADB_PASSWORD，直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 密碼需包含英文字母。|disallow=#@:/?|env=MARIADB_PASSWORD|allow_cancel=1
input=MARIADB_ROOT_PASSWORD|prompt=請輸入 root 密碼（MARIADB_ROOT_PASSWORD，直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB root 密碼需包含英文字母。|disallow=#@:/?|env=MARIADB_ROOT_PASSWORD|allow_cancel=1

success_extra=🔐 MariaDB root 密碼：${MARIADB_ROOT_PASSWORD}
success_extra=🔐 資料庫名稱：${MARIADB_DATABASE}
success_extra=🔐 資料庫帳號：${MARIADB_USER}
success_extra=🔐 資料庫密碼：${MARIADB_PASSWORD}
success_extra=ℹ️ 連線字串：mysql://${MARIADB_USER}:<pass>@<本機tailscaleIP>:${host_port}/${MARIADB_DATABASE}
success_warn=若你用既有資料目錄啟動，`MARIADB_ROOT_PASSWORD`、`MARIADB_DATABASE`、`MARIADB_USER`、`MARIADB_PASSWORD` 等初始化變數將不再生效；若要重跑初始化，請先備份再清空資料目錄。
success_warn=若其他節點要透過 Tailscale 連入，請到「Headscale → Tailnet 服務埠轉發」新增 TCP/${host_port}；TGDB 預設只綁 127.0.0.1，不直接暴露到公網。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/library/mariadb:11
