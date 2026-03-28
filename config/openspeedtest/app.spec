spec_version=1
display_name=OpenSpeedTest
image=docker.io/openspeedtest/latest:latest
doc_url=https://hub.docker.com/r/openspeedtest/latest
menu_order=94

access_policy=local_only

base_port=3777

input=https_port|prompt=OpenSpeedTest HTTPS 對外埠: |type=port|env=OPENSPEEDTEST_HTTPS_PORT|default_source=next_available_port|start=3778|avoid=host_port|check_available=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔒 HTTPS：https://${access_host}:${https_port}
success_warn= 若放在反向代理後方，請調整 proxy 的 post-body / client_max_body_size 至 35m 以上，修改ALLOW_ONLY，否則上傳測速可能失敗。
success_warn= HTTPS 預設為自簽憑證，瀏覽器出現安全警告屬正常現象（正式對外建議走反向代理/自備憑證）。

quadlet_type=single
quadlet_template=quadlet/default.container

