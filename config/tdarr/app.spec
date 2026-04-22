spec_version=1
display_name=Tdarr
image=ghcr.io/haveagitgat/tdarr:latest
doc_url=https://docs.tdarr.io/
menu_order=181

access_policy=local_only

base_port=38265
instance_subdirs=server configs logs
record_subdirs=server configs logs

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=共享影音資料根目錄
volume_subdirs=torrents usenet media subtitles tdarr_cache

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 建議在 Tdarr 內掃描 /data/media，暫存目錄用 /temp。
success_warn=這版 Tdarr 預設使用同 Pod 內的內建 Node（server + node 雙單元），只先開啟基本 CPU 流程；若你要 GPU / 多節點，請在「編輯紀錄」中再補 /dev/dri、NVIDIA runtime 或遠端 node 設定。
success_warn=若你要讓 Tdarr 與 Jellyfin / Arr 使用同一套媒體目錄，請保持共享根目錄一致，並在 Tdarr 內使用 /data/media/... 作為來源路徑。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=node|template=quadlet/default2.container|suffix=-node.container

update_pull_images=ghcr.io/haveagitgat/tdarr:latest
update_pull_images=ghcr.io/haveagitgat/tdarr_node:latest
