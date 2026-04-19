spec_version=1
display_name=Hermes Agent
image=docker.io/nousresearch/hermes-agent:latest
doc_url=https://hermes-agent.nousresearch.com/docs/user-guide/docker
menu_order=999

access_policy=local_only
hidden=1

base_port=8788
instance_subdirs=hermes-home workspace
record_subdirs=hermes-home workspace

cli_quick_args=api_port
input=api_port|prompt=請輸入 Hermes Gateway API 埠（預設 8642，輸入 0 取消）: |required=1|ask=1|default=8642|env=HERMES_API_PORT|allow_cancel=1
var=API_SERVER_KEY|source=random_hex|len=48

config=hermes-home/.env|template=configs/.env.example|mode=600|label=.env
config=hermes-home/SOUL.md|template=configs/SOUL.md.example|mode=600|label=SOUL.md

edit_files=hermes-home/SOUL.md hermes-home/.env

success_extra=🔌 Hermes Gateway API：http://127.0.0.1:${api_port}
success_extra=🔐 Hermes Gateway API Key：${API_SERVER_KEY}
success_extra=📁 工作區：${instance_dir}/workspace
success_warn=Hermes Agent 具備讀寫檔案、執行指令與網頁操作能力；請勿直接暴露到公網，建議僅本機/Tailscale/內網使用。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=dashboard|template=quadlet/default.container|suffix=.container
unit=gateway|template=quadlet/default2.container|suffix=-gateway.container

update_pull_images=docker.io/nousresearch/hermes-agent:latest
