spec_version=1
display_name=Recyclarr
image=ghcr.io/recyclarr/recyclarr:latest
doc_url=https://recyclarr.dev/guide/installation/docker/
menu_order=999

access_policy=local_only
hidden=1

base_port=12345
instance_subdirs=config
record_subdirs=config

touch_files=config/recyclarr.yml

config=.env|template=configs/.env.example|mode=600|label=.env
config=config/recyclarr.yml|template=configs/recyclarr.yml.example|mode=600|label=recyclarr.yml

success_warn=部署後請先編輯 ${instance_dir}/config/recyclarr.yml，填入 Prowlarr / Sonarr / Radarr / Lidarr 的網址與 API Key，再重啟或手動執行同步。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/recyclarr/recyclarr:latest
