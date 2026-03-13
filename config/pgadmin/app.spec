spec_version=1
display_name=pgAdmin 4
image=docker.io/dpage/pgadmin4:latest
doc_url=https://www.pgadmin.org/
menu_order=9000

hidden=1

base_port=5050
instance_subdirs=data
record_subdirs=data

cli_quick_args=email pass_word

input=email|prompt=請輸入 pgAdmin 登入 Email（PGADMIN_DEFAULT_EMAIL，不得為空，輸入 0 取消）: |required=1|no_space=1|env=PGADMIN_DEFAULT_EMAIL|allow_cancel=1
input=pass_word|prompt=請輸入 pgAdmin 密碼（PGADMIN_DEFAULT_PASSWORD，不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=PGADMIN_DEFAULT_PASSWORD|allow_cancel=1

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

full_remove_purge_record=1

success_extra=🔐 登入 Email：${email}
success_extra=🔐 登入密碼：${pass_word}

quadlet_type=single
quadlet_template=quadlet/default.container
