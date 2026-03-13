spec_version=1
display_name=Kopia（快照備份）
image=docker.io/kopia/kopia:20260223.0.231822
doc_url=https://github.com/kopia/kopia
menu_order=999

hidden=1

base_port=51115
access_policy=local_only

uses_volume_dir=1
volume_dir_prompt=Kopia Repository 資料目錄
instance_subdirs=config cache logs

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

input=KOPIA_PASSWORD|prompt=請輸入 Repository 密碼（用於加密/解密，不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=KOPIA_PASSWORD|allow_cancel=1
input=KOPIA_SERVER_USERNAME|prompt=請輸入 Web UI 帳號（預設 kopia；輸入 0 取消）: |required=1|no_space=1|default=kopia|ask=1|env=KOPIA_SERVER_USERNAME|allow_cancel=1
input=KOPIA_SERVER_PASSWORD|prompt=請輸入 Web UI 密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=KOPIA_SERVER_PASSWORD|allow_cancel=1

success_extra=🔐 Repository 密碼：${KOPIA_PASSWORD}
success_extra=🔐 Web UI 帳號：${KOPIA_SERVER_USERNAME}
success_extra=🔐 Web UI 密碼：${KOPIA_SERVER_PASSWORD}
success_extra=ℹ️ 本地快照存放=/repository，備份來源=/data。部署後會直接進入 rclone 遠端設定流程。

quadlet_type=single
quadlet_template=quadlet/default.container
