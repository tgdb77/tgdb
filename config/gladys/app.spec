spec_version=1
display_name=Gladys Assistant
image=docker.io/gladysassistant/gladys:v4
doc_url=https://github.com/GladysAssistant/Gladys
menu_order=122

access_policy=local_only

base_port=8118
instance_subdirs=data
record_subdirs=data

require_podman_socket=1

deploy_mode_default=rootful
compat_deploy_modes=rootful

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn= 為了支援家庭自動化/區網探索等需求，預設採 rootful + privileged + host network，並掛載 /dev、/run/udev，以及把 Podman API socket 掛到 /var/run/docker.sock。請只在可信任環境使用，並用防火牆/反代白名單限制來源。

quadlet_type=single
quadlet_template=quadlet/default.container
