spec_version=1
display_name=SerpBear
image=docker.io/towfiqi/serpbear:latest
doc_url=https://github.com/towfiqi/serpbear
menu_order=150

base_port=3222
access_policy=local_only

instance_subdirs=data
record_subdirs=data

cli_quick_args=admin_user admin_pass
input=admin_user|prompt=請輸入 SerpBear 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=SERPBEAR_ADMIN_USER|allow_cancel=1
input=admin_pass|prompt=請輸入 SerpBear 管理員密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=strong_password|len=20|no_space=1|env=SERPBEAR_ADMIN_PASS|allow_cancel=1

var=secret_key|source=random_hex|len=64
var=api_key|source=random_hex|len=40

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 管理員帳號：${admin_user}
success_extra=🔐 管理員密碼：${admin_pass}
success_extra=🔐 API Key：${api_key}
success_warn=若要從外部服務或腳本呼叫 SerpBear API，請妥善保存上方 API Key；之後若要輪替，可直接編輯 ${instance_dir}/.env 的 APIKEY 後重啟單元。
success_warn=若之後改成域名 / HTTPS / 反向代理，請同步調整 ${instance_dir}/.env 的 NEXT_PUBLIC_APP_URL，避免登入後跳轉或分享連結網址不正確。
success_warn=Google Search Console 整合預設未啟用；若要匯入資料，請依官方文件填入 SEARCH_CONSOLE_CLIENT_EMAIL 與 SEARCH_CONSOLE_PRIVATE_KEY。

quadlet_type=single
quadlet_template=quadlet/default.container
