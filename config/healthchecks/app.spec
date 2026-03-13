spec_version=1
display_name=Healthchecks
image=docker.io/healthchecks/healthchecks:v4.0
doc_url=https://healthchecks.io/docs/self_hosted_docker/
menu_order=50

base_port=8066
instance_subdirs=data
record_subdirs=data

cli_quick_args=admin_email admin_password
input=admin_email|prompt=請輸入超級管理員 Email（登入帳號；輸入 0 取消）: |required=1|no_space=1|pattern=^[^[:space:]@]+@[^[:space:]@]+$|pattern_msg=Email 格式不正確。|env=HEALTHCHECKS_ADMIN_EMAIL|allow_cancel=1
input=admin_password|prompt=請輸入超級管理員密碼（不得為空；輸入 0 取消）: |required=1|type=password|no_space=1|env=HEALTHCHECKS_ADMIN_PASSWORD|allow_cancel=1

var=secret_key|source=random_hex|len=64|env=HEALTHCHECKS_SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

post_deploy=scripts/post_deploy_create_superuser.sh|runner=bash

success_extra=🔐 超級管理員帳號：${admin_email}
success_extra=🔐 超級管理員密碼：${admin_password}
success_extra=ℹ️ 登入頁面：${http_url}/accounts/login/
success_warn=若日後改成域名或 HTTPS，請編輯 ${instance_dir}/.env 更新 SITE_ROOT 與 ALLOWED_HOSTS，然後執行更新/重啟。

quadlet_type=single
quadlet_template=quadlet/default.container
