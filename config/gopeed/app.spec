spec_version=1
display_name=Gopeed
image=docker.io/liwei2633/gopeed:latest
doc_url=https://gopeed.com/zh-TW/docs/install
menu_order=168

base_port=9995
instance_subdirs=storage
record_subdirs=storage

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=Gopeed 下載目錄

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn=若你要把 Gopeed 經由反向代理或公網 IP 對外提供，請先編輯 ${instance_dir}/.env 啟用 `GOPEED_USERNAME` / `GOPEED_PASSWORD`。
success_warn=若你要允許更多下載目錄，請調整 ${instance_dir}/.env 的 `GOPEED_WHITEDOWNLOADDIRS`。

quadlet_type=single
quadlet_template=quadlet/default.container
