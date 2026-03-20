spec_version=1
display_name=ConvertX
image=ghcr.io/c4illin/convertx:latest
doc_url=https://github.com/C4illin/ConvertX
menu_order=68

base_port=3033
instance_subdirs=data
record_subdirs=data

var=jwt_secret|source=random_hex|len=32|env=JWT_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 JWT Secret：${jwt_secret}
success_warn=若你之後改用非 HTTPS 的反向代理或非 localhost 直接存取，登入失敗時請編輯 ${instance_dir}/.env 將 `HTTP_ALLOWED=true`，但正式對外仍建議優先使用 HTTPS。

quadlet_type=single
quadlet_template=quadlet/default.container
