spec_version=1
display_name=Gatus
image=ghcr.io/twin/gatus:stable
doc_url=https://github.com/TwiN/gatus
menu_order=140

base_port=8386

instance_subdirs=config data
record_subdirs=config data

cli_quick_args=basic_auth_user basic_auth_password

input=basic_auth_user|prompt=請輸入 Gatus Basic Auth 帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=GATUS_BASIC_AUTH_USER|allow_cancel=1
input=basic_auth_password|prompt=請輸入 Gatus Basic Auth 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=20|no_space=1|max_len=72|env=GATUS_BASIC_AUTH_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config/config.yaml|template=configs/config.yaml.example|mode=600|label=config.yaml（Gatus 設定）

pre_deploy=scripts/pre_deploy_enable_basic_auth.sh|runner=bash|allow_fail=0

success_extra=🔐 Gatus Basic Auth 帳號：${basic_auth_user}
success_extra=🔐 Gatus Basic Auth 密碼：${basic_auth_password}
success_warn= 若你要監測 ICMP（ping），容器通常需要額外能力；根據需求編寫設定檔，建議優先使用 HTTP/TCP/DNS 檢查。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/twin/gatus:stable
