spec_version=1
display_name=Ackee
image=docker.io/electerious/ackee:latest
doc_url=https://github.com/electerious/Ackee
menu_order=162

base_port=3225

instance_subdirs=mongo
record_subdirs=mongo

cli_quick_args=admin_user admin_pass
input=admin_user|prompt=請輸入 Ackee 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=ACKEE_USERNAME|allow_cancel=1
input=admin_pass|prompt=請輸入 Ackee 管理員密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=strong_password|len=20|no_space=1|env=ACKEE_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 Ackee 管理員帳號：${admin_user}
success_extra=🔐 Ackee 管理員密碼：${admin_pass}
success_warn=Ackee 官方 app.json 明確要求 `ACKEE_ALLOW_ORIGIN`；TGDB 這裡先保守設成 `http://127.0.0.1:${host_port}` 並開 `ACKEE_AUTO_ORIGIN=true`。若你要追蹤正式站台，請務必編輯 ${instance_dir}/.env 把 `ACKEE_ALLOW_ORIGIN` 改成實際網站來源。
success_warn=若之後改成域名 / HTTPS，請同步檢查反向代理的 CORS 與 SSL 設定；Ackee tracker 走跨站請求，來源白名單與標頭設定會直接影響追蹤是否成功。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=mongo|template=quadlet/default2.container|suffix=-mongo.container

update_pull_images=docker.io/mongo:7
