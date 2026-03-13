spec_version=1
display_name=Wallos
image=docker.io/bellamy/wallos:latest
doc_url=https://github.com/ellite/Wallos
menu_order=39

base_port=3399

instance_subdirs=db logos
record_subdirs=db logos

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

quadlet_type=single
quadlet_template=quadlet/default.container

