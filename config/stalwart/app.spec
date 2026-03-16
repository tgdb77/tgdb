spec_version=1
display_name=Stalwart + Snappymail
image=docker.io/stalwartlabs/stalwart:latest
doc_url=https://stalwart.email/docs/install/platform/docker & https://github.com/the-djmaze/snappymail
menu_order=57

base_port=28080
instance_subdirs=stalwart snappymail
record_subdirs=stalwart snappymail

input=STALWART_ADMIN_PASSWORD|prompt=請輸入 Stalwart 管理員密碼（直接按 Enter 使用隨機密碼）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=STALWART_ADMIN_PASSWORD
input=SNAPPYMAIL_PORT|prompt=請輸入 SnappyMail Webmail 對外埠: |type=port|ask=1|default_source=next_available_port|start=28888|avoid=host_port|check_available=1|env=SNAPPYMAIL_PORT

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

post_deploy=scripts/post_deploy_snappymail_admin_password.sh|runner=bash

success_extra=🔐 Stalwart 管理帳號：admin
success_extra=🔐 Stalwart 管理密碼：${STALWART_ADMIN_PASSWORD}
success_extra=🛠️ Webmail 管理介面：http://${access_host}:${SNAPPYMAIL_PORT}/?admin
success_warn=Webmail 管理密碼亦可於以下檔案查詢：${instance_dir}/snappymail/_data_/_default_/admin_password.txt
success_warn=防火牆提醒：請依你的實際需求放行對應埠（SMTP/Submission/IMAP/ManageSieve 等），並正確設定 DNS 紀錄（MX/SPF/DKIM/DMARC），否則可能無法正常收發信。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=snappymail|template=quadlet/default2.container|suffix=-snappymail.container
