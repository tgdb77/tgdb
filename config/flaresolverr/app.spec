spec_version=1
display_name=FlareSolverr
image=ghcr.io/flaresolverr/flaresolverr:latest
doc_url=https://github.com/FlareSolverr/FlareSolverr
menu_order=88

base_port=38191

access_policy=local_only

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ API 端點：${http_url}/v1
success_warn=強烈建議只讓同機服務（例如 Prowlarr）透過 http://host.containers.internal:${host_port}/v1 呼叫；不要直接暴露到公網，避免被濫用造成資源耗盡。
success_warn=瀏覽器請求很吃記憶體；若同時併發請求過多，可能導致 OOM 或服務不穩。

quadlet_type=single
quadlet_template=quadlet/default.container
