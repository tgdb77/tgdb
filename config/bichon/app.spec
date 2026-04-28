spec_version=1
display_name=Bichon
image=docker.io/rustmailer/bichon:latest
doc_url=https://github.com/rustmailer/bichon
menu_order=199

access_policy=local_only

base_port=15633

uses_volume_dir=1
volume_dir_prompt=Bichon 郵件封存資料目錄
volume_subdirs=bichon-data
cli_quick_args=volume_dir

var=encrypt_password|source=random_hex|len=48|env=BICHON_ENCRYPT_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 預設內建管理員帳密：admin / admin@bichon 登入後自行更換。
success_warn= Bichon 預設未設定 BICHON_CORS_ORIGINS 時會允許所有來源；若你之後要對外提供瀏覽器存取，建議在 ${instance_dir}/.env 明確填入受信任來源。
success_warn= 若你之後改成自訂域名或 HTTPS，請同步修改 ${instance_dir}/.env 的 BICHON_PUBLIC_URL，避免 API / Browser 存取行為異常。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/rustmailer/bichon:latest
