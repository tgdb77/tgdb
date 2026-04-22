spec_version=1
display_name=Unpackerr
image=ghcr.io/unpackerr/unpackerr:latest
doc_url=https://unpackerr.zip/docs/install/docker/
menu_order=183

access_policy=local_only

base_port=35656
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=共享影音資料根目錄
volume_subdirs=torrents usenet media subtitles tdarr_cache

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 指標端點：${http_url}/metrics
success_warn=部署後請先編輯 ${instance_dir}/.env，填入 Sonarr / Radarr / Lidarr / Bazarr / Whisparr 的 URL 與 API Key；未填前容器雖可啟動，但不會實際解壓。
success_warn=若其他服務也是獨立容器，URL 請一律使用 host.containers.internal 搭配 TGDB 的主機側埠，不要在容器內寫 127.0.0.1。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/unpackerr/unpackerr:latest
