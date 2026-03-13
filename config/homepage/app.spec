spec_version=1
display_name=Homepage
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
