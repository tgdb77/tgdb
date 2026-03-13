spec_version=1
display_name=IT-Tools
image=docker.io/corentinth/it-tools:latest
doc_url=https://github.com/CorentinTh/it-tools
menu_order=38

base_port=3388

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

quadlet_type=single
quadlet_template=quadlet/default.container

