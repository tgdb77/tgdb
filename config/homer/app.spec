spec_version=1
display_name=Homer
image=docker.io/b4bz/homer:latest
doc_url=https://github.com/bastienwirtz/homer
menu_order=191

base_port=8301
instance_subdirs=assets
record_subdirs=assets

config=.env|template=configs/.env.example|mode=600|label=.env
config=assets/config.yml|template=configs/config.yml.example|mode=644|label=assets/config.yml

edit_files=assets/config.yml

success_extra=ℹ️ 儀表板設定檔：${instance_dir}/assets/config.yml
success_extra=ℹ️ 你也可以把自訂圖示、背景圖或其他靜態檔放進 ${instance_dir}/assets/。
success_warn=若你要把 Homer 掛到子路徑（例如 /homer），請編輯 ${instance_dir}/.env 的 SUBFOLDER，並同步調整反向代理設定。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/b4bz/homer:latest
