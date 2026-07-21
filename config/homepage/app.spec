spec_version=1
cli_quick_args=none
display_name=Homepage
description=可自訂的服務儀表板，用來集中顯示常用連結、服務狀態與整合小工具。
image=ghcr.io/gethomepage/homepage:latest
doc_url=https://gethomepage.dev/
menu_order=12

base_port=3300
instance_subdirs=config
record_subdirs=config

require_podman_socket=1

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=ℹ️ 反代完成後，請編輯 ${instance_dir}/.env，將環境變數 HOMEPAGE_ALLOWED_HOSTS 加入你的域名（用逗號分隔）。

quadlet_type=single
quadlet_template=quadlet/default.container
