spec_version=1
display_name=Hemmelig
image=docker.io/hemmeligapp/hemmelig:v7
doc_url=https://github.com/HemmeligOrg/Hemmelig.app
menu_order=96

base_port=3910

instance_subdirs=database
record_subdirs=database

uses_volume_dir=1
volume_dir_prompt=上傳目錄

cli_quick_args=volume_dir auth_secret
input=auth_secret|prompt=請輸入 BETTER_AUTH_SECRET（直接按 Enter 使用隨機值，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=64|env=HEMMELIG_BETTER_AUTH_SECRET|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn= 首次部署完成後，請確認 .env 內的 BETTER_AUTH_URL / HEMMELIG_BASE_URL 為你實際訪問網址（反向代理/HTTPS 時尤其重要）。
success_warn= 預設隨意註冊帳號，正式上線須設定OIDC/SMTP做身分驗證。

quadlet_type=single
quadlet_template=quadlet/default.container
