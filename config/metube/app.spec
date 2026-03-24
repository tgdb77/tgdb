spec_version=1
display_name=MeTube
image=ghcr.io/alexta69/metube:latest
doc_url=https://github.com/alexta69/metube
menu_order=75

base_port=8881

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=下載目錄

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

quadlet_type=single
quadlet_template=quadlet/default.container
