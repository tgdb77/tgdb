spec_version=1
display_name=OpenCode
image=ghcr.io/anomalyco/opencode
doc_url=https://github.com/anomalyco/opencode
menu_order=120

access_policy=local_only

base_port=14096
instance_subdirs=config data state
record_subdirs=config data state

cli_quick_args=server_user server_pass
input=server_user|prompt=請輸入 OpenCode 基本認證帳號（預設 opencode；輸入 0 取消）: |required=1|ask=1|no_space=1|default=opencode|env=OPENCODE_SERVER_USERNAME|allow_cancel=1
input=server_pass|prompt=請輸入 OpenCode 基本認證密碼（直接按 Enter 使用強密碼；輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=strong_password|len=24|env=OPENCODE_SERVER_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 OpenCode 基本認證帳號：${server_user}
success_extra=🔐 OpenCode 基本認證密碼：${server_pass}
success_warn=OpenCode 具備執行指令/讀寫檔案等能力，請勿直接暴露到公網。若要遠端使用，建議先用 Tailscale/內網。

quadlet_type=single
quadlet_template=quadlet/default.container
