spec_version=1
display_name=Owncast
image=docker.io/owncast/owncast:latest
doc_url=https://owncast.online/docs/
menu_order=83

access_policy=local_only

base_port=8345

cli_quick_args=rtmp_port
input=rtmp_port|prompt=RTMP 對外埠（用於 OBS 推流）: |type=port|ask=1|env=OWNCAST_RTMP_PORT|allow_cancel=1|cli_zero_as_default=1|default_source=next_available_port|start=1995|avoid=host_port|check_available=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=📡 RTMP：rtmp://127.0.0.1:${rtmp_port}/live
success_warn=首次啟動後請到 Web 的 /admin (預設帳密：admin/abc123記得改)完成管理者/串流設定（實際路徑依 Owncast 版本為準）。
success_warn=若要讓「其他主機」的 OBS 推流，請把 Quadlet 的 RTMP PublishPort 改成 0.0.0.0，並自行設定防火牆/路由器僅允許可信來源。

quadlet_type=single
quadlet_template=quadlet/default.container

