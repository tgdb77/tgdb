spec_version=1
display_name=Sonarr
image=lscr.io/linuxserver/sonarr:latest
doc_url=https://docs.linuxserver.io/images/docker-sonarr/
menu_order=177

access_policy=local_only

base_port=38989
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=共享影音資料根目錄
volume_subdirs=torrents usenet media subtitles tdarr_cache

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn=請在 Sonarr 內把 Root Folder、下載路徑與 qBittorrent / Unpackerr 保持同一套容器路徑（建議都用 /data/...），避免失去 hardlink 與 instant move。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=lscr.io/linuxserver/sonarr:latest
