spec_version=1
display_name=FossFLOW
image=docker.io/stnsmith/fossflow:latest
doc_url=https://github.com/stan-smith/FossFLOW
menu_order=201

access_policy=local_only

base_port=8300

uses_volume_dir=1
volume_dir_prompt=FossFLOW 圖表資料目錄
cli_quick_args=volume_dir 

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn= 若把 ENABLE_SERVER_STORAGE 改成 false，後端儲存服務不會啟動；此時圖表僅能依瀏覽器端流程自行匯出 / 保存，不會寫入圖表資料目錄。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/stnsmith/fossflow:latest
