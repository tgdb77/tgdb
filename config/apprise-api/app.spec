spec_version=1
display_name=Apprise API
image=docker.io/caronc/apprise:latest
doc_url=https://github.com/caronc/apprise-api
menu_order=134

access_policy=local_only

base_port=8385

instance_subdirs=config attach plugin
record_subdirs=config attach plugin

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn= 本範本預設開啟 APPRISE_ADMIN=y，方便透過 Web UI 建立與管理通知設定；若要公開到外網，建議搭配反向代理與額外認證。
success_warn= 若你之後要自訂 Apprise plugin，可放到 ${instance_dir}/plugin。

quadlet_type=single
quadlet_template=quadlet/default.container
