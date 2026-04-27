spec_version=1
display_name=Slink
image=docker.io/anirdev/slink:latest
doc_url=https://docs.slinkapp.io/installation/01-docker-compose/
menu_order=190

base_port=3462
instance_subdirs=data
record_subdirs=data

uses_volume_dir=1
volume_dir_prompt=Slink 圖片資料目錄
cli_quick_args=admin_user admin_email admin_password volume_dir

input=admin_user|prompt=請輸入 Slink 初始管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|min_len=3|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=ADMIN_USERNAME|allow_cancel=1
input=admin_email|prompt=請輸入 Slink 初始管理員 Email（預設 admin@example.com，輸入 0 取消）: |required=1|ask=1|default=admin@example.com|no_space=1|pattern=^[^[:space:]@]+@[^[:space:]@]+$|pattern_msg=請輸入有效的 Email。|env=ADMIN_EMAIL|allow_cancel=1
input=admin_password|prompt=請輸入 Slink 初始管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=24|min_len=8|no_space=1|env=ADMIN_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 初始管理員帳號：${admin_user}
success_extra=🔐 初始管理員 Email：${admin_email}
success_extra=🔐 初始管理員密碼：${admin_password}
success_warn=若之後要改成正式域名或 HTTPS，請同步調整 ${instance_dir}/.env 的 ORIGIN 與 REQUIRE_SSL，避免 cookie、登入或反代行為異常。
success_warn=ADMIN_USERNAME / ADMIN_EMAIL / ADMIN_PASSWORD 主要用於首次初始化；完成後若你不想長期保留在 .env，可自行移除後重啟。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/anirdev/slink:latest
