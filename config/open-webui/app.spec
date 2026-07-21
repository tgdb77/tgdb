spec_version=1
cli_quick_args=none
display_name=Open WebUI
description=AI 對話網頁介面，可連接本機或遠端模型並管理聊天紀錄。
image=ghcr.io/open-webui/open-webui:main-slim
doc_url=https://github.com/open-webui/open-webui
menu_order=21

base_port=3366
instance_subdirs=open-webui
record_subdirs=open-webui

var=webui_secret_key|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 預設關閉 RAG 提升啟動速度，根據需求修改 .env 開啟。
success_warn= 若要對外提供服務，建議使用 Nginx 反向代理（HTTPS）並設定強密碼；並修改 ${instance_dir}/.env 中設定 CORS_ALLOW_ORIGIN 為你的域名。

quadlet_type=single
quadlet_template=quadlet/default.container
