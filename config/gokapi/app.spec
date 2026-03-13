spec_version=1
display_name=Gokapi
image=docker.io/f0rc3/gokapi:latest
doc_url=https://github.com/Forceu/Gokapi
menu_order=26

base_port=5384
instance_subdirs=config custom
record_subdirs=config custom

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=Volume 資料目錄（Gokapi 檔案資料）

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=ℹ️ 首次需訪問 ${http_url}/setup 初始化，完成後訪問 ${http_url}/admin 進入後台。

quadlet_type=single
quadlet_template=quadlet/default.container
