spec_version=1
display_name=code-server
image=docker.io/codercom/code-server:latest
doc_url=https://coder.com/docs/code-server/install
menu_order=61

base_port=8996
instance_subdirs=config local project
record_subdirs=config local project

cli_quick_args=pass_word
input=pass_word|prompt=請輸入 code-server 登入密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 登入密碼：${pass_word}
success_extra=專案目錄：${instance_dir}/project

quadlet_type=single
quadlet_template=quadlet/default.container
