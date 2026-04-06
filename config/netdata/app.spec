spec_version=1
display_name=Netdata
image=docker.io/netdata/netdata:stable
doc_url=https://github.com/netdata/netdata
menu_order=118

hidden=1
access_policy=local_only

base_port=19999
instance_subdirs=config lib cache
record_subdirs=config lib

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

require_podman_socket=1

success_extra=ℹ️ 若你希望多採集 rootful 容器指標，需要再次部屬並修改 quadlet 中的 podman.sock 來源。

quadlet_type=single
quadlet_template=quadlet/default.container
