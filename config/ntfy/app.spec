spec_version=1
display_name=ntfy
image=docker.io/binwiederhier/ntfy:latest
doc_url=https://github.com/binwiederhier/ntfy
menu_order=127

access_policy=local_only

base_port=9002
instance_subdirs=cache config
record_subdirs=cache config

cli_quick_args=admin_user admin_pass

input=admin_user|prompt=請輸入 ntfy 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=NTFY_ADMIN_USER|allow_cancel=1|cli_zero_as_default=1
input=admin_pass|prompt=請輸入 ntfy 管理員密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=strong_password|len=24|env=NTFY_ADMIN_PASS|allow_cancel=1|cli_zero_as_default=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config/server.yml|template=configs/server.yml.example|mode=600|label=server.yml

post_deploy=scripts/post_deploy_create_admin.sh|runner=bash|allow_fail=0

success_extra=👤 管理員帳號：${admin_user}
success_extra=🔐 管理員密碼：${admin_pass}
success_warn= 本範本預設關閉註冊（auth-default-access: deny-all），且僅允許已建立的使用者存取；部署完成後會自動用 CLI 建立上述管理員。
success_warn= 若要用 HTTPS 公開到外網，須將 server.yml 中的 base-url 改成對外域名。

quadlet_type=single
quadlet_template=quadlet/default.container

