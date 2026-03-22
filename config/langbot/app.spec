spec_version=1
display_name=LangBot
image=docker.io/rockchin/langbot:latest
doc_url=https://github.com/langbot-app/LangBot
menu_order=69

base_port=5353
instance_subdirs=data data/plugins
record_subdirs=data data/plugins

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

edit_files=data/config.yaml

success_extra=ℹ️ 若要設定 Webhook/反向代理前綴，請編輯 ${instance_dir}/data/config.yaml 的 api.webhook_prefix（例：https://your.domain.com）
success_extra=ℹ️ 若需要 QQ/NapCat/Lagrange 等反向 WS，請編輯 ${container_name}.pod 取消註釋 2280-2290 的 PublishPort 後重啟。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=plugin_runtime|template=quadlet/default2.container|suffix=-plugin-runtime.container
