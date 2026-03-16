spec_version=1
display_name=Draw.io
image=docker.io/jgraph/drawio:latest
doc_url=https://github.com/jgraph/drawio
menu_order=58

base_port=8089

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

quadlet_type=single
quadlet_template=quadlet/default.container
