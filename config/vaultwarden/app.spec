spec_version=1
display_name=Vaultwarden
image=docker.io/vaultwarden/server:latest
doc_url=https://github.com/dani-garcia/vaultwarden/wiki
menu_order=10

base_port=8008
instance_subdirs=vw-data
record_subdirs=vw-data

input=domain|prompt=請輸入 Vaultwarden 完整域名（例如 https://vw.example.com）: |required=1|ask=1|type=url|env=DOMAIN|allow_cancel=1

pre_deploy=scripts/pre_deploy_admin_token.sh|runner=bash|allow_fail=0
post_deploy=scripts/post_deploy_show_admin_token.sh|runner=bash|allow_fail=0

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔑 Admin 管理頁面：${domain}/admin
success_warn=vaultwarden 必須使用 SSL 證書訪問（Nginx 反代或 Cloudflare Tunnel）
success_warn=建立第一個帳號後，建議將 SIGNUPS_ALLOWED=false 並備份 ADMIN_TOKEN

quadlet_type=single
quadlet_template=quadlet/default.container

