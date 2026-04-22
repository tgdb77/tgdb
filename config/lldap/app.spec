spec_version=1
display_name=LLDAP
image=ghcr.io/lldap/lldap:latest-alpine-rootless
doc_url=https://github.com/lldap/lldap
menu_order=186

access_policy=local_only

base_port=17177
instance_subdirs=data
record_subdirs=data

cli_quick_args=ldap_port admin_password base_dn
input=ldap_port|prompt=請輸入 LDAP 對外埠（預設 3990，輸入 0 取消）: |required=1|ask=1|type=port|default=3990|avoid=host_port|check_available=1|env=LLDAP_LDAP_PORT|allow_cancel=1|cli_zero_as_default=1
input=admin_password|prompt=請輸入 LLDAP 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=24|min_len=8|no_space=1|env=LLDAP_LDAP_USER_PASS|allow_cancel=1|cli_zero_as_default=1
input=base_dn|prompt=請輸入 LDAP Base DN（預設 dc=example,dc=com，輸入 0 取消）: |required=1|ask=1|default=dc=example,dc=com|no_space=1|env=LLDAP_LDAP_BASE_DN|allow_cancel=1

var=jwt_secret|source=random_hex|len=64|env=LLDAP_JWT_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=🔐 管理員登入帳號：admin
success_extra=🔐 管理員密碼：${admin_password}
success_extra=ℹ️ LDAP：127.0.0.1:${ldap_port}
success_extra=ℹ️ Base DN：${base_dn}
success_warn= LDAP 埠通常只給其他內部服務使用；TGDB 這裡為了通用性也幫你綁到 127.0.0.1:${ldap_port}。若要讓其他節點連入，請自行評估反代、Tailnet 轉發或網路配置。
success_warn= 若你未來要讓其他服務做唯讀 LDAP 查詢，建議不要直接用 admin，而是在 LLDAP 裡另外建立屬於 `lldap_strict_readonly` 或 `lldap_password_manager` 群組的帳號。
success_warn= 若你之後改成正式域名或 HTTPS，請編輯 ${instance_dir}/.env 的 LLDAP_HTTP_URL，避免密碼重設連結或外部回呼網址異常。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/lldap/lldap:latest-alpine-rootless
