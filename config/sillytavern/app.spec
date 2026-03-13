spec_version=1
display_name=SillyTavern
image=ghcr.io/sillytavern/sillytavern:latest
doc_url=https://github.com/SillyTavern/SillyTavern
menu_order=29

base_port=8787
instance_subdirs=config data plugins extensions

config_template=configs/config.yaml
config_dest=config/config.yaml
config_mode=600
config_label=config.yaml（伺服器設定）

success_extra=🔒 白名單：若出現 Forbidden，請編輯 ${instance_dir}/config/config.yaml 的 whitelist/whitelistMode，然後重啟容器。

quadlet_type=single
quadlet_template=quadlet/default.container
