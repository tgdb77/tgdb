spec_version=1
display_name=Bazarr
image=lscr.io/linuxserver/bazarr:latest
doc_url=https://docs.linuxserver.io/images/docker-bazarr/
menu_order=180

access_policy=local_only

base_port=36767
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=共享影音資料根目錄
volume_subdirs=torrents usenet media subtitles tdarr_cache

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn=Bazarr 需要能看到與 Sonarr / Radarr 相同的媒體根目錄；請在三者內都使用一致的容器路徑（例如 /data/media/...），不要一邊用 /tv、一邊用 /data/media/tv。
success_warn=若字幕要寫回媒體資料夾，請確認 ${volume_dir} 的實際目錄權限允許目前使用者寫入。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=lscr.io/linuxserver/bazarr:latest
