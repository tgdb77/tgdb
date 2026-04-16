spec_version=1
display_name=MeiliSearch
image=docker.io/getmeili/meilisearch:v1.42.1
doc_url=https://www.meilisearch.com/docs/resources/self_hosting/getting_started/docker
menu_order=154

base_port=7788
access_policy=local_only

instance_subdirs=meili_data
record_subdirs=meili_data

var=master_key|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 Master Key：${master_key}
success_warn=請妥善保存 master key，之後若更換既有 API keys 也會一併失效。
success_warn=若你的應用只需要查詢功能，建議部署後用 master key 呼叫 `/keys` 建立較低權限的 Search API Key，不要把 master key 直接暴露給前端。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/getmeili/meilisearch:v1.42.1
