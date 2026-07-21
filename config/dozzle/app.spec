spec_version=1
cli_quick_args=none
display_name=Dozzle
description=即時查看與搜尋容器日誌的 Web 工具。
image=docker.io/amir20/dozzle:latest
doc_url=https://dozzle.dev/
menu_order=51

base_port=8077
access_policy=local_only

instance_subdirs=data
record_subdirs=data

require_podman_socket=1

config=.env|template=configs/.env.example|mode=600|label=.env

quadlet_type=single
quadlet_template=quadlet/default.container
