spec_version=1
display_name=Netdata
image=docker.io/netdata/netdata:stable
doc_url=https://github.com/netdata/netdata
menu_order=118

access_policy=local_only

compat_deploy_modes=rootless rootful

base_port=19999
instance_subdirs=config lib cache
record_subdirs=config lib

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

require_podman_socket=1

success_extra=ℹ️ Netdata 會掛載 Podman API socket（docker.sock）以採集容器指標；請確保面板僅限可信來源存取。
success_extra=ℹ️ 若要監控 rootful 容器，請以 rootful 模式重新部屬；若要監控 rootless 容器，請以 rootless 模式部屬。

quadlet_type=single
quadlet_template=quadlet/default.container
