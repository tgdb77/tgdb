spec_version=1
display_name=Twenty
image=docker.io/twentycrm/twenty:latest
doc_url=https://docs.twenty.com/developers/self-host/capabilities/docker-compose
menu_order=71

base_port=3888
instance_subdirs=pgdata rdata local-storage
record_subdirs=pgdata rdata local-storage

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 PostgreSQL 帳號（預設 twenty；輸入 0 取消）: |required=1|ask=1|no_space=1|default=postgres|allow_cancel=1
input=db_pass|prompt=請輸入 PostgreSQL 密碼（僅允許英文/數字/底線；輸入 0 取消）: |required=1|type=password|no_space=1|pattern=^[A-Za-z0-9_]+$|pattern_msg=PostgreSQL 避免特殊字元造成資料庫連線字串解析失敗。|allow_cancel=1

var=app_secret|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_warn=⚠️ Twenty 需要正確的 SERVER_URL 才能在反代/HTTPS 下正常運作；若你將它掛到域名，請編輯 ${instance_dir}/.env 把 SERVER_URL 改成 https://你的域名 後重啟單元。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=server|template=quadlet/default.container|suffix=.container
unit=worker|template=quadlet/default4.container|suffix=-worker.container
unit=db|template=quadlet/default2.container|suffix=-db.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=docker.io/postgres:16
update_pull_images=docker.io/redis:7
