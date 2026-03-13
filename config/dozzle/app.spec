spec_version=1
display_name=Dozzle
image=docker.io/amir20/dozzle:latest
doc_url=https://dozzle.dev/
menu_order=51

base_port=8077
access_policy=local_only

instance_subdirs=data
record_subdirs=data

require_podman_socket=1

quadlet_type=single
quadlet_template=quadlet/default.container
