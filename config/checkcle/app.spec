spec_version=1
display_name=CheckCle
image=docker.io/operacle/checkcle:latest
doc_url=https://docs.checkcle.io/getting-started/quickstart
menu_order=92

base_port=8999

instance_subdirs=pb_data
record_subdirs=pb_data

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 預設帳號：admin@example.com
success_extra=🔐 預設密碼：Admin123456
success_warn= 請在首次登入後立即變更預設帳號與密碼，避免被未授權存取。

quadlet_type=single
quadlet_template=quadlet/default.container

