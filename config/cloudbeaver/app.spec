spec_version=1
display_name=CloudBeaver
image=docker.io/dbeaver/cloudbeaver:latest
doc_url=https://dbeaver.com/docs/cloudbeaver/Server-configuration/
menu_order=9002

hidden=1
access_policy=local_only

base_port=8978
instance_subdirs=workspace
record_subdirs=workspace

cli_quick_args=admin_user admin_pass

input=admin_user|prompt=請輸入 CloudBeaver 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=管理員帳號僅可使用英數、點、底線與連字號。|env=CB_ADMIN_NAME|allow_cancel=1
input=admin_pass|prompt=請輸入 CloudBeaver 管理員密碼（直接按 Enter 使用隨機密碼）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=CB_ADMIN_PASSWORD

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

full_remove_purge_record=1

success_extra=🔐 管理員帳號：${admin_user}
success_extra=🔐 管理員密碼：${admin_pass}

quadlet_type=single
quadlet_template=quadlet/default.container
