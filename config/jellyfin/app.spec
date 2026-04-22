spec_version=1
display_name=Jellyfin
image=ghcr.io/jellyfin/jellyfin:latest
doc_url=https://jellyfin.org/
menu_order=14

base_port=38069
instance_subdirs=config  data logs
record_subdirs=config  data logs

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=共享影音資料根目錄
volume_subdirs=torrents usenet media subtitles tdarr_cache
volume_dir_propagation=ask
volume_dir_propagation_ask_value=shared
volume_dir_propagation_default=none

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 建議在 Jellyfin 內把媒體庫指向 /data/media/movies、/data/media/tv、/data/media/music。
success_warn=若你要搭配 Sonarr / Radarr / Lidarr / Tdarr，共享資料根目錄請直接選同一個 volume_dir，避免後續路徑對不起來。
success_warn=如需硬體加速（VAAPI/QuickSync/NVIDIA 等），可在「編輯紀錄」中按需取消註解 Device/GroupAdd 等設定。

quadlet_type=single
quadlet_template=quadlet/default.container
