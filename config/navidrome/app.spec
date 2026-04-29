spec_version=1
display_name=Navidrome
image=docker.io/deluan/navidrome:latest
doc_url=https://github.com/deluan/navidrome
menu_order=9

base_port=4545
instance_subdirs=data
record_subdirs=data

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=Volume 目錄

volume_dir_propagation=rshared

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/deluan/navidrome:latest
