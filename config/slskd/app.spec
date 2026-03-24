spec_version=1
display_name=Slskd
image=docker.io/slskd/slskd:latest
doc_url=https://github.com/slskd/slskd
menu_order=70

base_port=5033
instance_subdirs=app
record_subdirs=app

cli_quick_args=slsk_user slsk_pass

input=web_user|prompt=請輸入 slskd Web UI 帳號（預設 slskd，輸入 0 取消）: |required=1|no_space=1|ask=1|default=slskd|env=SLSKD_USERNAME|allow_cancel=1
input=web_pass|prompt=請輸入 slskd Web UI 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=SLSKD_PASSWORD|allow_cancel=1

input=slsk_user|prompt=請輸入 Soulseek 帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|env=SLSKD_SLSK_USERNAME|allow_cancel=1
input=slsk_pass|prompt=請輸入 Soulseek 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=SLSKD_SLSK_PASSWORD|allow_cancel=1

input=listen_port|prompt=請輸入 Soulseek 連入埠（預設 50300，輸入 0 取消）: |required=1|no_space=|ask=1|default=50300|env=SLSKD_SLSK_LISTEN_PORT|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

edit_files=app/slskd.yml

success_extra=🔐 Web UI 帳號：${web_user}
success_extra=🔐 Web UI 密碼：${web_pass}
success_extra=🔐 Soulseek 帳號：${slsk_user}
success_extra=🔐 Soulseek 密碼：${slsk_pass}
success_warn=傳輸提醒：請確保已放行 ${listen_port}/TCP（防火牆/安全群組/NAT 轉發），否則 Soulseek 連入可能受限。
success_warn=安全提醒：若你將 Web UI 反向代理到公網，請務必改密碼，並慎用 SLSKD_REMOTE_CONFIGURATION=true。

quadlet_type=single
quadlet_template=quadlet/default.container
