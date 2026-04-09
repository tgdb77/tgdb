spec_version=1
display_name=Pocket ID
image=ghcr.io/pocket-id/pocket-id:v2
doc_url=https://pocket-id.org/docs/setup/installation/
menu_order=139

base_port=1441

instance_subdirs=data
record_subdirs=data

cli_quick_args=fqdn
input=fqdn|prompt=請輸入 Pocket ID 對外網域（例：id.example.com，輸入 0 取消）: |required=1|ask=1|no_space=1|pattern=^[^[:space:]]+[.][^[:space:]]+$|pattern_msg=請輸入有效的 FQDN（例：id.example.com）。|env=POCKET_ID_FQDN|allow_cancel=1

var=encryption_key|source=random_hex|len=64|env=ENCRYPTION_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn= 盡速訪問 /setup 路徑進行註冊、初始化。
success_warn= Pocket ID 涉及 Passkey / WebAuthn 與 OIDC，正式使用請讓 https://${fqdn} 能由瀏覽器正常存取，並保持 ${instance_dir}/.env 的 APP_URL 與實際公開網址一致。
success_warn= 若未來要讓同機容器以內網方式存取 issuer，可再按官方文件補上 INTERNAL_APP_URL。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/pocket-id/pocket-id:v2
