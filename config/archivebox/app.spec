spec_version=1
display_name=ArchiveBox
image=docker.io/archivebox/archivebox:latest
doc_url=https://docs.archivebox.io/dev/Docker.html
menu_order=62

base_port=8001
instance_subdirs=data sonic
record_subdirs=data sonic

input=admin_user|prompt=請輸入 ArchiveBox 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=管理員帳號僅可使用英數、點、底線與連字號。|env=ADMIN_USERNAME|allow_cancel=1
input=admin_pass|prompt=請輸入 ArchiveBox 管理員密碼（直接按 Enter 使用隨機密碼）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=ADMIN_PASSWORD
var=search_password|source=random_hex|len=32|env=SEARCH_BACKEND_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=sonic.cfg|template=configs/sonic.cfg.example|mode=600|label=Sonic 設定

success_extra=🔐 管理員帳號：${admin_user}
success_extra=🔐 管理員密碼：${admin_pass}
success_extra=ℹ️ CLI 新增網址：podman exec -it --user archivebox ${container_name} archivebox add 'https://example.com'
success_warn=若要改成透過 Nginx / 正式域名對外提供，請同步調整 ${instance_dir}/.env 的 LISTEN_HOST、ALLOWED_HOSTS 與 CSRF_TRUSTED_ORIGINS，然後重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=sonic|template=quadlet/default2.container|suffix=-sonic.container

update_pull_images=docker.io/archivebox/sonic:latest
