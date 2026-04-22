spec_version=1
display_name=Prowlarr
image=lscr.io/linuxserver/prowlarr:latest
doc_url=https://docs.linuxserver.io/images/docker-prowlarr/
menu_order=179

access_policy=local_only

base_port=39696
instance_subdirs=config
record_subdirs=config

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 建議盡速在 Prowlarr 完成 indexer 與 download client 設定，再把 Sonarr / Radarr / Lidarr 連回 Prowlarr。
success_warn=若你有部署 FlareSolverr，建議在 Prowlarr 內填 http://host.containers.internal:38191/v1，不要在容器內寫 127.0.0.1。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=lscr.io/linuxserver/prowlarr:latest
