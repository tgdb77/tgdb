spec_version=1
display_name=PhotoPrism
image=docker.io/photoprism/photoprism:latest
doc_url=https://docs.photoprism.app/getting-started/docker-compose/
menu_order=167

base_port=2324

instance_subdirs=storage mysql
record_subdirs=storage mysql

uses_volume_dir=1
volume_dir_prompt=照片資料目錄
volume_subdirs=originals import
cli_quick_args=admin_user admin_pass db_user db_pass volume_dir

input=admin_user|prompt=請輸入 PhotoPrism 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=PHOTOPRISM_ADMIN_USER|allow_cancel=1
input=admin_pass|prompt=請輸入 PhotoPrism 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=random_hex|len=24|env=PHOTOPRISM_ADMIN_PASSWORD|allow_cancel=1|cli_zero_as_default=1
input=db_user|prompt=請輸入 MariaDB 帳號（預設 photoprism，輸入 0 取消）: |required=1|ask=1|default=photoprism|no_space=1|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 帳號需包含英文字母。|env=MARIADB_USER|allow_cancel=1|cli_zero_as_default=1
input=db_pass|prompt=請輸入 MariaDB 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=random_hex|len=32|pattern=.*[A-Za-z].*|pattern_msg=MariaDB 密碼需包含英文字母。|env=MARIADB_PASSWORD|allow_cancel=1|cli_zero_as_default=1

var=mariadb_root_password|source=random_hex|len=32|env=MARIADB_ROOT_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PhotoPrism 管理員帳號：${admin_user}
success_extra=🔐 PhotoPrism 管理員密碼：${admin_pass}
success_extra=🔐 MariaDB 帳號：${db_user}
success_extra=🔐 MariaDB 密碼：${db_pass}
success_warn= 若要透過自訂域名或 HTTPS 反代，請編輯 ${instance_dir}/.env 調整 PHOTOPRISM_SITE_URL，再重啟單元，避免登入跳轉、分享連結或資源網址異常。
success_warn= PhotoPrism 與 MariaDB 的初始化帳密主要用於首次啟動；若之後需要變更管理員密碼，請依官方文件用應用內或 CLI 流程修改，不要只改 .env。
success_warn= 若照片量很大或主機記憶體偏小，首次索引/縮圖可能較久；建議將 originals 放在容量較大的磁碟。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=mariadb|template=quadlet/default2.container|suffix=-mariadb.container

update_pull_images=docker.io/mariadb:11
