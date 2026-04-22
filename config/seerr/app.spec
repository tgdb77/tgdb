spec_version=1
display_name=Seerr
image=ghcr.io/seerr-team/seerr:latest
doc_url=https://docs.seerr.dev/getting-started/docker
menu_order=176

base_port=35055
instance_subdirs=config
record_subdirs=config

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn=若要讓 Seerr 連到 Jellyfin / Sonarr / Radarr，建議在容器內使用 host.containers.internal 搭配 TGDB 的主機側埠（例如 http://host.containers.internal:38069）。
success_warn=若之後要改成正式域名或 HTTPS 反代，請到 Seerr 後台更新 Application URL，避免 OAuth 回呼、通知連結或分享網址異常。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/seerr-team/seerr:latest
