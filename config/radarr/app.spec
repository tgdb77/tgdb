spec_version=1
display_name=Radarr
image=lscr.io/linuxserver/radarr:latest
doc_url=https://docs.linuxserver.io/images/docker-radarr/
menu_order=178

access_policy=local_only

base_port=37878
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=共享影音資料根目錄
volume_subdirs=torrents usenet media subtitles tdarr_cache

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn=請在 Radarr 內把電影 Root Folder 與下載客戶端路徑統一成 /data/...，這樣從 qBittorrent 搬檔時才能保留 hardlink / atomic move。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=lscr.io/linuxserver/radarr:latest
