spec_version=1
cli_quick_args=none
display_name=Beszel-hub
description=集中查看伺服器與服務的監控資料。
image=docker.io/henrygd/beszel
doc_url=https://github.com/henrygd/beszel
menu_order=163

base_port=8899

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 盡速建立管理員帳號。

quadlet_type=single
quadlet_template=quadlet/default.container
