spec_version=1
display_name=Whisparr
image=ghcr.io/hotio/whisparr:v3
doc_url=https://wiki.servarr.com/whisparr/installation/docker
menu_order=999

access_policy=local_only
hidden=1

base_port=36969
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=共享影音資料根目錄
volume_subdirs=torrents usenet media subtitles tdarr_cache

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn=Whisparr v3 為 Docker 優先版本；建議把下載路徑、媒體根目錄與下載客戶端統一成 /data/...，避免 copy + delete 與匯入失敗。
success_warn=部屬即代表使用者在管轄地已具備完全行為能力，相關責任自行承擔。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/hotio/whisparr:v3
