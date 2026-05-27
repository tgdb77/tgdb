spec_version=1
display_name=Beszel-hub
image=docker.io/henrygd/beszel
doc_url=https://github.com/henrygd/beszel
menu_order=163

base_port=8899

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 盡速建立管理員帳號。

quadlet_type=single
quadlet_template=quadlet/default.container
