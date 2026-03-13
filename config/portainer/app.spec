spec_version=1
display_name=Portainer
image=docker.io/portainer/portainer-ce:lts
doc_url=https://www.portainer.io/
menu_order=11

base_port=9999
instance_subdirs=portainer_data
record_subdirs=portainer_data

require_podman_socket=1

quadlet_type=single
quadlet_template=quadlet/default.container
