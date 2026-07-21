spec_version=1
cli_quick_args=none
display_name=Portainer
description=容器管理平台，可透過 Web UI 管理容器、映像、網路、Volume 與環境資源。
image=docker.io/portainer/portainer-ce:lts
doc_url=https://www.portainer.io/
menu_order=11

base_port=9999
instance_subdirs=portainer_data
record_subdirs=portainer_data

require_podman_socket=1

quadlet_type=single
quadlet_template=quadlet/default.container
