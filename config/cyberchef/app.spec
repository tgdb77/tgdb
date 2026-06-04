spec_version=1
display_name=CyberChef
description=提供瀏覽器中的資料編碼、解碼、加密與格式轉換工具。
image=ghcr.io/gchq/cyberchef:10
doc_url=https://github.com/gchq/CyberChef#running-locally-with-docker
menu_order=84

access_policy=local_only

base_port=8885

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn=若要追最新版，請把映像從 ghcr.io/gchq/cyberchef:10 改成 :latest（可能包含破壞性變更）。

quadlet_type=single
quadlet_template=quadlet/default.container

