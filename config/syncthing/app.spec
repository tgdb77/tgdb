spec_version=1
display_name=Syncthing
image=docker.io/syncthing/syncthing:latest
doc_url=https://syncthing.net/
menu_order=13

base_port=8483

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=Volume 資料目錄

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=ℹ️ 若需外網同步/直連，請自訂 Quadlet 額外開放 22000/tcp、22000/udp、21027/udp（多實例需自行調整埠號）。

quadlet_type=single
quadlet_template=quadlet/default.container
