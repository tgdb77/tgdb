spec_version=1
display_name=Stash
image=docker.io/stashapp/stash:latest
doc_url=https://docs.stashapp.cc/installation/docker/
menu_order=69

access_policy=local_only

base_port=1212

instance_subdirs=config metadata cache blobs generated
record_subdirs=config metadata cache blobs generated

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=媒體收藏目錄（掛載到容器 /data）

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

edit_files=config/config.yml

success_extra=🧩 設定/插件：${instance_dir}/config（掛載到 /root/.stash）
success_warn=若要啟用 DLNA 功能，需改用 host network（請參考官方 Docker 文件並手動調整 Quadlet：Network=host，且移除 PublishPort）。

quadlet_type=single
quadlet_template=quadlet/default.container

