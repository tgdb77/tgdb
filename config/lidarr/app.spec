spec_version=1
display_name=Lidarr
image=lscr.io/linuxserver/lidarr:latest
doc_url=https://docs.linuxserver.io/images/docker-lidarr/
menu_order=182

access_policy=local_only

base_port=38686
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=共享影音資料根目錄
volume_subdirs=torrents usenet media subtitles tdarr_cache

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn=Lidarr 的音樂庫、下載路徑與下載客戶端也建議統一用 /data/...；若容器內路徑不同，後續自動整理與 hardlink 會變成 copy + delete。
success_warn=若你後續還要接 Navidrome / Jellyfin，請把最終音樂庫整理到固定子目錄（例如 /data/media/music）。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=lscr.io/linuxserver/lidarr:latest
