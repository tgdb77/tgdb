spec_version=1
display_name=Opengist
image=ghcr.io/thomiceli/opengist:1
doc_url=https://opengist.io/docs/installation/docker.html
menu_order=202

base_port=6167

instance_subdirs=data
record_subdirs=data

cli_quick_args=ssh_port
input=ssh_port|prompt=請輸入 Opengist Git SSH 對外埠（預設 2332，輸入 0 取消）: |required=1|ask=1|type=port|default=2332|avoid=host_port|check_available=1|env=OPENGIST_SSH_PORT|allow_cancel=1|cli_zero_as_default=1

var=opengist_secret_key|source=random_hex|len=64

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 首次註冊的使用者會成為管理員。
success_extra=🔑 Git over SSH：127.0.0.1:${ssh_port}
success_warn= 建議首次登入後立即到 Admin 將 Disable signup 開啟；若是私人用途，也可一併啟用 Require login。
success_warn= 若改用正式域名或反向代理，請同步調整 ${instance_dir}/.env 的 OG_EXTERNAL_URL；若 Git SSH 使用不同域名，再補上 OG_SSH_EXTERNAL_DOMAIN。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/thomiceli/opengist:1
