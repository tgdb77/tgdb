spec_version=1
display_name=Stirling-PDF
image=docker.io/stirlingtools/stirling-pdf:latest
doc_url=https://github.com/Stirling-Tools/Stirling-PDF
menu_order=37

base_port=3377

instance_subdirs=configs customFiles logs pipeline
record_subdirs=configs customFiles logs pipeline

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_warn= 反代到域名後，請務必編輯 ${instance_dir}/.env 設定 SYSTEM_ROOTURI=https://你的域名（否則部分連結/回呼可能不正確），並重啟單元。

quadlet_type=single
quadlet_template=quadlet/default.container
