spec_version=1
display_name=Semaphore UI
image=docker.io/semaphoreui/semaphore:v2.17.33
doc_url=https://semaphoreui.com/docs/admin-guide/installation/docker
menu_order=141

base_port=3002

instance_subdirs=data tmp
record_subdirs=data tmp

cli_quick_args=admin_user admin_password admin_name admin_email
input=admin_user|prompt=請輸入 Semaphore 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=SEMAPHORE_ADMIN|allow_cancel=1
input=admin_password|prompt=請輸入 Semaphore 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=20|no_space=1|env=SEMAPHORE_ADMIN_PASSWORD|allow_cancel=1
input=admin_name|prompt=請輸入 Semaphore 管理員名稱（預設 Admin，輸入 0 取消）: |required=1|ask=1|default=Admin|env=SEMAPHORE_ADMIN_NAME|allow_cancel=1
input=admin_email|prompt=請輸入 Semaphore 管理員 Email（預設 admin@localhost，輸入 0 取消）: |required=1|ask=1|no_space=1|default=admin@localhost|pattern=^[^[:space:]@]+@[^[:space:]@]+$|pattern_msg=請輸入有效的 Email。|env=SEMAPHORE_ADMIN_EMAIL|allow_cancel=1

var=access_key_encryption|source=random_hex|len=32|env=SEMAPHORE_ACCESS_KEY_ENCRYPTION
var=cookie_hash|source=random_hex|len=32|env=SEMAPHORE_COOKIE_HASH
var=cookie_encryption|source=random_hex|len=32|env=SEMAPHORE_COOKIE_ENCRYPTION

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 管理員帳號：${admin_user}
success_extra=🔐 管理員密碼：${admin_password}
success_warn= 若你要透過 Nginx 對外提供服務，請務必一併轉發 `/api/ws` WebSocket，並保留 `proxy_buffering off` / `proxy_request_buffering off`。若改成子路徑，請再設定 `${instance_dir}/.env` 的 `SEMAPHORE_WEB_ROOT`。
success_warn= Semaphore 會在容器內執行 Ansible / Terraform / OpenTofu 等工作；首次實戰前請確認 SSH 金鑰、inventory、git 憑證與 playbook/暫存目錄權限是否符合需求。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/semaphoreui/semaphore:v2.17.33
