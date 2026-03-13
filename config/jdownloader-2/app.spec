spec_version=1
display_name=JDownloader 2
image=docker.io/jlesage/jdownloader-2:latest
doc_url=https://github.com/jlesage/docker-jdownloader-2
menu_order=23

base_port=5858
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir pass_word
volume_dir_prompt=下載目錄

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

# 必填：VNC 密碼（強制啟用；若包含空白會造成 EnvironmentFile 解析問題，因此禁止空白）
input=pass_word|prompt=請輸入 VNC 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|env=JDOWNLOADER_2_VNC_PASSWORD|allow_cancel=1

success_extra=🔐 VNC 密碼：${pass_word}
success_extra=ℹ️ MyJDownloader：請在 JDownloader 內登入 MyJDownloader 帳號；一般不需額外參數。
success_extra=ℹ️ 下載輸出：已掛載 ${volume_dir} 到容器 /output。

quadlet_type=single
quadlet_template=quadlet/default.container
