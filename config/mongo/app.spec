spec_version=1
display_name=MongoDB
image=docker.io/library/mongo:8.0.17
doc_url=https://github.com/docker-library/mongo
menu_order=5

access_policy=local_only

base_port=27017
instance_subdirs=mongo
record_subdirs=mongo

cli_quick_args=MONGO_INITDB_ROOT_USERNAME MONGO_INITDB_ROOT_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

input=MONGO_INITDB_ROOT_USERNAME|prompt=請輸入 MongoDB root 帳號（預設 root，輸入 0 取消）: |required=1|no_space=1|ask=1|default=root|pattern=^[A-Za-z0-9._-]+$|pattern_msg=帳號僅可使用英數、點、底線與連字號。|env=MONGO_INITDB_ROOT_USERNAME|allow_cancel=1
input=MONGO_INITDB_ROOT_PASSWORD|prompt=請輸入 MongoDB root 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=32|no_space=1|env=MONGO_INITDB_ROOT_PASSWORD|allow_cancel=1

success_extra=🔐 MongoDB root 帳號：${MONGO_INITDB_ROOT_USERNAME}
success_extra=🔐 MongoDB root 密碼：${MONGO_INITDB_ROOT_PASSWORD}
success_extra=ℹ️ 連線字串：mongodb://${MONGO_INITDB_ROOT_USERNAME}:<MONGO_INITDB_ROOT_PASSWORD>@<本機tailscaleIP>:${host_port}/admin?authSource=admin
success_warn=`MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD` 只會在資料目錄首次初始化時生效；若 ${instance_dir}/mongo 已經有既有資料，之後再改這些值不會自動重建帳號。
success_warn=若其他節點要透過 Tailscale 連入，請到「Headscale → Tailnet 服務埠轉發」新增 TCP/${host_port}；TGDB 預設只綁 127.0.0.1，不直接暴露到公網。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/library/mongo:8.0.17
