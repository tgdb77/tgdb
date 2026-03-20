spec_version=1
display_name=Web-Check
image=docker.io/lissy93/web-check:latest
doc_url=https://github.com/Lissy93/web-check
menu_order=67

base_port=3454

access_policy=local_only

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn=預設不需要任何設定即可啟動；若你之後填入 `REACT_APP_*` API 金鑰，請注意這些值屬於前端可見範圍，只應使用最小權限的金鑰。
success_warn=Web-Check 會主動對外發送多種查詢；若你的主機網路受限、缺少外網 DNS / traceroute / Chromium 能力，部分檢查可能會顯示失敗或被略過。

quadlet_type=single
quadlet_template=quadlet/default.container
