spec_version=1
display_name=Home Assistant
image=ghcr.io/home-assistant/home-assistant:stable
doc_url=https://github.com/home-assistant/core
menu_order=123

base_port=8321
instance_subdirs=config
record_subdirs=config

# Home Assistant 常見需要 host network + 讀取硬體/區網探索（mDNS/SSDP/UDP broadcast 等），建議用 rootful。
deploy_mode_default=rootful
compat_deploy_modes=rootful

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config/configuration.yaml|template=configs/configuration.yaml.example|mode=600|label=configuration.yaml（初始設定）

success_warn= 本範本預設採 rootful + privileged + host network，適合家庭自動化/區網探索，但風險較高：服務會在主機上直接監聽 ${host_port}（可能可被同網段存取）。請只在可信任環境使用，並搭配防火牆白名單/反代策略限制來源。

quadlet_type=single
quadlet_template=quadlet/default.container

