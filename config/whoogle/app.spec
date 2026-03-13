spec_version=1
display_name=Whoogle
image=ghcr.io/benbusby/whoogle-search:latest
doc_url=https://github.com/benbusby/whoogle-search
menu_order=15

base_port=5555
instance_subdirs=config
record_subdirs=config

cli_quick_args=user_name pass_word
input=user_name|prompt=請輸入 Whoogle 基本認證帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|allow_cancel=1
input=pass_word|prompt=請輸入 Whoogle 基本認證密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|allow_cancel=1

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

success_extra=🔐 基本認證帳號：${user_name}
success_extra=🔐 基本認證密碼：${pass_word}

quadlet_type=single
quadlet_template=quadlet/default.container
