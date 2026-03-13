spec_version=1
display_name=Webtop
image=lscr.io/linuxserver/webtop:debian-xfce
doc_url=https://docs.linuxserver.io/images/docker-webtop/
menu_order=53

base_port=3080
instance_subdirs=config
record_subdirs=config

cli_quick_args=user_name pass_word

input=user_name|prompt=請輸入 Webtop 登入帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|env=WEBTOP_USER_NAME|allow_cancel=1
input=pass_word|prompt=請輸入 Webtop 登入密碼（不得為空，輸入 0 取消）: |required=1|type=password|env=WEBTOP_PASSWORD|allow_cancel=1

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=🔐 登入帳號：${user_name}
success_extra=🔐 登入密碼：${pass_word}

quadlet_type=single
quadlet_template=quadlet/default.container
