spec_version=1
display_name=OpenList
image=docker.io/openlistteam/openlist:latest-aio
doc_url=https://github.com/openlistteam/openlist
menu_order=28

base_port=9487

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=Volume 資料目錄
volume_dir_propagation=ask
volume_dir_propagation_default=rshared

var=jwt_secret|source=random_hex|len=32

config_template=configs/default.conf
config_dest=config.json
config_mode=600
config_label=config.json

success_extra=ℹ️ 預設密碼請用「查看單元日誌」取得，登入後請立即更改。

quadlet_type=single
quadlet_template=quadlet/default.container
