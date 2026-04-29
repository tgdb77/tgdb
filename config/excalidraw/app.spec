spec_version=1
display_name=Excalidraw
image=docker.io/excalidraw/excalidraw:latest
doc_url=https://github.com/excalidraw/excalidraw
menu_order=1

base_port=8088

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

quadlet_type=single
quadlet_template=quadlet/default.container
update_pull_images=docker.io/excalidraw/excalidraw:latest
