spec_version=1
display_name=N8n
image=docker.n8n.io/n8nio/n8n
doc_url=https://docs.n8n.io/
menu_order=19

base_port=8765
instance_subdirs=n8n_data local-files
record_subdirs=n8n_data local-files

cli_quick_args=user_name pass_word

input=user_name|prompt=請輸入 n8n 基本認證帳號（不得為空，輸入 0 取消）: |required=1|no_space=1|env=N8N_USER_NAME|allow_cancel=1
input=pass_word|prompt=請輸入 n8n 基本認證密碼（不得為空，輸入 0 取消）: |required=1|type=password|env=N8N_PASSWORD|allow_cancel=1

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=🔐 基本認證帳號：${user_name}
success_extra=🔐 基本認證密碼：${pass_word}

quadlet_type=single
quadlet_template=quadlet/default.container
