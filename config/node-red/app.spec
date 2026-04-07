spec_version=1
display_name=Node-RED
image=docker.io/nodered/node-red:latest
doc_url=https://github.com/node-red/node-red
menu_order=124

access_policy=local_only

base_port=1888
instance_subdirs=data
record_subdirs=data

cli_quick_args=user_name pass_word

input=user_name|prompt=請輸入 Node-RED 管理帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|allow_cancel=1
input=pass_word|prompt=請輸入 Node-RED 管理密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=20|no_space=1|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=auth.env|template=configs/auth.env.example|mode=600|label=auth.env

pre_deploy=scripts/pre_deploy_generate_settings.sh|runner=bash|allow_fail=0

success_extra=🔐 Node-RED 管理帳號：${user_name}
success_extra=🔐 Node-RED 管理密碼：${pass_word}

success_warn= adminAuth 只保護 Node-RED Editor / Admin API 務必留存；若流程有 HTTP In、Dashboard 等對外路由，請另外加上驗證或反向代理存取控制。
success_warn= TGDB 預設僅綁 127.0.0.1，請勿直接對外公開；若需要對外提供服務，建議用 Nginx HTTPS 反向代理並搭配防火牆白名單限制來源 IP。

quadlet_type=single
quadlet_template=quadlet/default.container
