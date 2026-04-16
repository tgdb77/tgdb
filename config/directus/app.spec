spec_version=1
display_name=Directus
image=docker.io/directus/directus:latest
doc_url=https://docs.directus.io/self-hosted/quickstart
menu_order=153

base_port=8219

instance_subdirs=database extensions templates
record_subdirs=database extensions templates

uses_volume_dir=1
volume_dir_prompt=上傳目錄

cli_quick_args=admin_email admin_pass
input=admin_email|prompt=請輸入 Directus 初始管理員 Email（預設 admin@example.com，輸入 0 取消）: |required=1|ask=1|default=admin@example.com|no_space=1|pattern=^[^[:space:]@]+@[^[:space:]@]+$|pattern_msg=請輸入有效的 Email。|env=DIRECTUS_ADMIN_EMAIL|allow_cancel=1
input=admin_pass|prompt=請輸入 Directus 初始管理員密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=strong_password|len=20|no_space=1|env=DIRECTUS_ADMIN_PASSWORD|allow_cancel=1

var=secret|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 初始管理員 Email：${admin_email}
success_extra=🔐 初始管理員密碼：${admin_pass}
success_warn=若之後要改用 PostgreSQL / MySQL / Redis 快取，可直接編輯 ${instance_dir}/.env 補上對應 `DB_*` / `CACHE_*` / `REDIS` 設定後重啟單元。
success_warn=若之後改成域名 / HTTPS / 反向代理，請務必同步設定 ${instance_dir}/.env 的 `PUBLIC_URL`；否則 OAuth、忘記密碼信件與公開連結可能會指到錯誤位址。
success_warn=若要自行安裝本地 extensions，可放到 ${instance_dir}/extensions；若要自動重載，可把 `EXTENSIONS_AUTO_RELOAD=true` 加入 ${instance_dir}/.env 後重啟。

quadlet_type=single
quadlet_template=quadlet/default.container
