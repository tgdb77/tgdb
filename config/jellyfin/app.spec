spec_version=1
display_name=Jellyfin
image=ghcr.io/jellyfin/jellyfin:latest
doc_url=https://jellyfin.org/
menu_order=14

base_port=8069
instance_subdirs=config cache data logs
record_subdirs=config cache data logs

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=Volume 目錄（Jellyfin 媒體來源，掛載到 /media）
volume_dir_propagation=ask
volume_dir_propagation_ask_value=shared
volume_dir_propagation_default=none

config_template=configs/.env.example
config_dest=.env
config_label=.env（環境變數）

success_extra=ℹ️ 媒體目錄：已掛載 ${volume_dir} 到容器 /media。
success_extra=ℹ️ 如需硬體加速（VAAPI/QuickSync/NVIDIA 等），可在「編輯紀錄」中按需取消註解 Device/GroupAdd 等設定。

quadlet_type=single
quadlet_template=quadlet/default.container
