spec_version=1
display_name=Pinchflat
image=ghcr.io/kieraneglin/pinchflat:dev
doc_url=https://github.com/kieraneglin/pinchflat
menu_order=27

base_port=8954
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir user_name pass_word

config_dest=.env
config_mode=600
config_label=.env（環境變數）

config_template=configs/.env.example

input=user_name|prompt=請輸入 Pinchflat Basic Auth 帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|allow_cancel=1
input=pass_word|prompt=請輸入 Pinchflat Basic Auth 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|allow_cancel=1

volume_dir_prompt=Volume 下載目錄

success_extra=🔐 Basic Auth 帳號：${user_name}
success_extra=🔐 Basic Auth 密碼：${pass_word}

quadlet_type=single
quadlet_template=quadlet/default.container
