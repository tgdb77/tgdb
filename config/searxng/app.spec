spec_version=1
display_name=SearXNG
image=docker.io/searxng/searxng:latest
doc_url=https://github.com/searxng/searxng-docker
menu_order=45

base_port=5566
instance_subdirs=searxng data valkey_data
record_subdirs=searxng data valkey_data

var=secret_key|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=searxng/settings.yml|template=configs/settings.yml.example|mode=600|label=settings.yml（SearXNG 設定）
config=searxng/limiter.toml|template=configs/limiter.toml.example|mode=600|label=limiter.toml（限流設定）

success_extra=ℹ️ 若使用反向代理，請把 ${instance_dir}/.env 的 SEARXNG_BASE_URL 改為你的正式 HTTPS 網址。
success_extra=ℹ️ 若要公開服務，建議將 ${instance_dir}/searxng/settings.yml 的 server.limiter 調整為 true。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=valkey|template=quadlet/default2.container|suffix=-valkey.container

update_pull_images=docker.io/valkey/valkey:8-alpine
