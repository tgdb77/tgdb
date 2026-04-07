spec_version=1
display_name=Karakeep
image=ghcr.io/karakeep-app/karakeep:release
doc_url=https://github.com/karakeep-app/karakeep
menu_order=128

base_port=3004
instance_subdirs=data meili_data
record_subdirs=data meili_data

var=nextauth_secret|source=random_hex|len=64|env=NEXTAUTH_SECRET
var=meili_master_key|source=random_hex|len=64|env=MEILI_MASTER_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn= 盡速創建初始管理員，並到 ${instance_dir}/.env 中開啟 DISABLE_SIGNUPS 關閉註冊。
success_warn= 若要用 HTTPS 公開到外網，請到 ${instance_dir}/.env 中的 NEXTAUTH_URL 改成對外域名。
success_warn= 若你要啟用 AI 自動標籤（OpenAI），請到 ${instance_dir}/.env 設定 OPENAI_API_KEY，並重新部署/重啟服務。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=web|template=quadlet/default.container|suffix=.container
unit=chrome|template=quadlet/default2.container|suffix=-chrome.container
unit=meilisearch|template=quadlet/default3.container|suffix=-meilisearch.container

update_pull_images=gcr.io/zenika-hub/alpine-chrome:124
update_pull_images=docker.io/getmeili/meilisearch:v1.37.0

