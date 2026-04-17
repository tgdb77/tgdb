spec_version=1
display_name=Beszel-agent
image=docker.io/henrygd/beszel-agent:latest
doc_url=https://github.com/henrygd/beszel
menu_order=164

base_port=45786
require_podman_socket=1

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

cli_quick_args=KEY TOKEN HUB_URL

input=KEY|prompt=請輸入 Beszel Agent KEY（不得為空，輸入 0 取消）: |required=1|type=password|env=BESZEL_AGENT_KEY|allow_cancel=1
input=TOKEN|prompt=請輸入 Beszel Agent TOKEN（不得為空，輸入 0 取消）: |required=1|type=password|env=BESZEL_AGENT_TOKEN|allow_cancel=1
input=HUB_URL|prompt=請輸入 Beszel HUB_URL（不得為空，輸入 0 取消）: |required=1|env=BESZEL_AGENT_HUB_URL|allow_cancel=1

success_extra=ℹ️ 請到 Beszel Hub 確認此 agent 是否開始回報數據。

quadlet_type=single
quadlet_template=quadlet/default.container
