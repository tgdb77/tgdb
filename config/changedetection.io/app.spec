spec_version=1
display_name=ChangeDetection.io
image=ghcr.io/dgtlmoon/changedetection.io
doc_url=https://github.com/dgtlmoon/changedetection.io
menu_order=16

base_port=5656

instance_subdirs=changedetection-data
record_subdirs=changedetection-data

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=ℹ️ 反代完成後，請編輯 ChangeDetection.io 的 Quadlet/紀錄，將環境變數 BASE_URL 改成你的域名並取消註釋。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=browser|template=quadlet/default2.container|suffix=-browser.container

update_pull_images=docker.io/dgtlmoon/sockpuppetbrowser:latest
