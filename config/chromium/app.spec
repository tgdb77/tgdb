spec_version=1
display_name=Chromium
image=docker.io/jlesage/chromium:latest
doc_url=https://github.com/jlesage/docker-chromium
menu_order=24

base_port=5885
instance_subdirs=config
record_subdirs=config

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

# Chromium：需要 VNC 密碼（強制啟用；若包含空白會造成 EnvironmentFile 解析問題，因此禁止空白）
cli_quick_args=pass_word
input=pass_word|prompt=請輸入 VNC 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|env=CHROMIUM_VNC_PASSWORD|allow_cancel=1

success_extra=🔐 VNC 密碼：${pass_word}
success_extra=ℹ️ 下載位置：預設會落在容器 /config（主機對應 ${instance_dir}/config）。

quadlet_type=single
quadlet_template=quadlet/default.container
