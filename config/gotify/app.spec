spec_version=1
display_name=Gotify
image=docker.io/gotify/server:latest
doc_url=https://github.com/gotify/server
menu_order=49

base_port=5252

instance_subdirs=data
record_subdirs=data

cli_quick_args=admin_user admin_pass
input=admin_user|prompt=請輸入 Gotify 初始管理員帳號（預設 admin；輸入 0 取消）: |required=1|ask=1|no_space=1|default=admin|env=GOTIFY_ADMIN_USER|allow_cancel=1
input=admin_pass|prompt=請輸入 Gotify 初始管理員密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=GOTIFY_ADMIN_PASS|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 Gotify 管理員帳號：${admin_user}
success_extra=🔐 Gotify 管理員密碼：${admin_pass}
success_warn= GOTIFY_DEFAULTUSER_* 僅在「首次初始化資料庫」時生效；若已初始化，請改在 Web UI 變更帳密。
success_warn= 反代到域名後，請確認反代標頭與 HTTPS 設定，避免推播連線位址不正確。

quadlet_type=single
quadlet_template=quadlet/default.container

