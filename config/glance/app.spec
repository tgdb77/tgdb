spec_version=1
display_name=Glance
image=docker.io/glanceapp/glance:latest
doc_url=https://github.com/glanceapp/glance
menu_order=129

access_policy=local_only

base_port=8100
instance_subdirs=config assets
record_subdirs=config assets

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config/glance.yml|template=configs/glance.yml.example|mode=600|label=glance.yml
config=config/home.yml|template=configs/home.yml.example|mode=600|label=home.yml
config=assets/user.css|template=configs/user.css.example|mode=644|label=user.css

success_extra=ℹ️ 根據需求修改/添加相關 .yml
success_warn= 要讓 Glance 能讀取容器狀態。需在 Quadlet 取消註解 docker.sock 掛載，並確認面板僅限可信來源存取。

quadlet_type=single
quadlet_template=quadlet/default.container

