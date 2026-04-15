spec_version=1
display_name=RustFS
image=docker.io/rustfs/rustfs:latest
doc_url=https://github.com/rustfs/rustfs
menu_order=148

base_port=9101

instance_subdirs=logs
record_subdirs=logs

uses_volume_dir=1
volume_dir_prompt=資料磁碟目錄
volume_dir_propagation=ask
volume_dir_propagation_default=none

cli_quick_args=volume_dir s3_port access_key secret_key

input=s3_port|prompt=請輸入 RustFS S3 API 對外埠（預設 9010，輸入 0 取消）: |required=1|ask=1|type=port|default=9010|avoid=host_port|check_available=1|env=RUSTFS_S3_PORT|allow_cancel=1|cli_zero_as_default=1
input=access_key|prompt=請輸入 RustFS access key（預設 rustfsadmin，輸入 0 取消）: |required=1|ask=1|default=rustfsadmin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=RUSTFS_ACCESS_KEY|allow_cancel=1|cli_zero_as_default=1
input=secret_key|prompt=請輸入 RustFS secret key（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=strong_password|len=24|no_space=1|env=RUSTFS_SECRET_KEY|allow_cancel=1|cli_zero_as_default=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🖥️ RustFS S3 API：http://127.0.0.1:${s3_port}
success_extra=🔐 access key：${access_key}
success_extra=🔐 secret key：${secret_key}
success_warn= 預設僅綁定 127.0.0.1；若要對外提供，建議走 Nginx / HTTPS 反向代理，並先把 RUSTFS_EXTERNAL_ADDRESS= 換成正式值。
success_warn= 若你之後要改成多磁碟節點，請同時編輯 ${instance_dir}/.env 的 RUSTFS_VOLUMES 與 ${container_name}.container 的 Volume 掛載。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/rustfs/rustfs:latest
