spec_version=1
display_name=Komga
image=docker.io/gotson/komga:latest
doc_url=https://komga.org/docs/installation/docker
menu_order=160

base_port=25666

instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
volume_dir_prompt=Komga 資料目錄

cli_quick_args=volume_dir

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 盡速創建初始管理員。
success_warn=若之後要對外提供，官方文件強烈建議使用 HTTPS，因為 Komga 會用到 HTTP Basic Authentication。若你要改成域名 / HTTPS / 子路徑，請依官方配置文件調整對應參數與反向代理。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/gotson/komga:1.23.6
