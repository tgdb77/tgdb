spec_version=1
display_name=Homebox
image=ghcr.io/sysadminsmedia/homebox:latest
doc_url=https://homebox.software/en/quick-start/install/
menu_order=34

base_port=3111

instance_subdirs=data
record_subdirs=data

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

quadlet_type=single
quadlet_template=quadlet/default.container
