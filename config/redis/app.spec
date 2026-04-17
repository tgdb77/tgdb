spec_version=1
display_name=Redis
image=docker.io/redis:7-alpine
doc_url=https://github.com/redis/redis
menu_order=3

base_port=6379
access_policy=local_only

instance_subdirs=rdata
record_subdirs=rdata

cli_quick_args=REDIS_PASSWORD

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

input=REDIS_PASSWORD|prompt=請輸入 Redis 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=REDIS_PASSWORD|allow_cancel=1

success_extra=🔐 redis 密碼：${REDIS_PASSWORD}
success_extra=ℹ️ 其他節點要用 tailscale IP 連入：請到「Headscale → Tailnet 服務埠轉發」新增 TCP/${host_port}。
success_extra=ℹ️ 連線字串：redis://:<pass>@<本機tailscaleIP>:${host_port}

quadlet_type=single
quadlet_template=quadlet/default.container
