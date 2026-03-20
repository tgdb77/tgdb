spec_version=1
display_name=Trilium
image=docker.io/triliumnext/notes:latest
doc_url=https://github.com/TriliumNext/Trilium
menu_order=64

base_port=8994
instance_subdirs=data
record_subdirs=data

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn=若你有同步中的桌面端 / 行動端裝置，建議固定 image tag 而非長期使用 `latest`，並在升級時同步更新全部成員，避免同步協定版本不一致。
success_warn=Trilium 啟動新版本時會自動遷移資料庫；遷移後舊版本將無法直接讀取，因此正式升級前請先保留備份。

quadlet_type=single
quadlet_template=quadlet/default.container
