spec_version=1
display_name=SeaweedFS
image=docker.io/chrislusf/seaweedfs:latest
doc_url=https://github.com/seaweedfs/seaweedfs
menu_order=25

# Filer HTTP（對外主入口）
base_port=8989
instance_subdirs=master filer pgdata
record_subdirs=master filer pgdata

# 避免檔案掛載目標不存在時，被 Podman 建成同名資料夾
touch_files=.env filer.toml s3.json security.toml init-filemeta.sql

uses_volume_dir=1
volume_dir_prompt=Volume 資料目錄（SeaweedFS Volume Server）
volume_dir_propagation=ask
volume_dir_propagation_default=none
volume_dir_propagation_ask_value=rshared

# CLI：6 <idx> 1 <name|0> <port|0> <volume_dir|0> <pass_word> [s3_port] [user_name] [bucket_name]
cli_quick_args=volume_dir pass_word s3_port user_name bucket_name

input=pass_word|prompt=請輸入 SeaweedFS 密碼（S3 secretKey / PostgreSQL 密碼；不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|env=SEAWEEDFS_PASSWORD|allow_cancel=1

# S3 對外埠：第二個埠號（避免與 host_port 相同；預設從 8383 起找下一個可用）
input=s3_port|prompt=S3 對外埠（127.0.0.1）|type=port|ask=1|env=SEAWEEDFS_S3_PORT|allow_cancel=1|cli_zero_as_default=1|default_source=next_available_port|start=8383|avoid=host_port|check_available=1

input=user_name|prompt=帳號（USER_NAME / accessKey）：|default=seaweedfs|no_space=1|ask=1|env=SEAWEEDFS_USER_NAME|cli_zero_as_default=1
input=bucket_name|prompt=儲存桶名稱（bucket_name；不可包含空白或 /）：|default=seaweedfs|no_space=1|disallow=/|ask=1|env=SEAWEEDFS_BUCKET_NAME|cli_zero_as_default=1

# JWT：用於安全簽章；由 security.toml 使用
var=jwt_key|source=random_hex|len=64|env=SEAWEEDFS_JWT_KEY

# 多設定檔（v2-1）
config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=filer.toml|template=configs/filer.toml|mode=600|label=filer.toml（Metadata Store）
config=s3.json|template=configs/s3.json|mode=600|label=s3.json（S3 身分）
config=security.toml|template=configs/security.toml|mode=600|label=security.toml（JWT/CORS）
config=init-filemeta.sql|template=configs/init-filemeta.sql|mode=644|label=init-filemeta.sql（DB 初始化）

# 部署後初始化：自動建立 filer 的 buckets 目錄（不影響服務啟動；失敗僅警告）
post_deploy=scripts/post_deploy_init_buckets.sh|runner=bash|allow_fail=1

success_extra=ℹ️ Filer：127.0.0.1:${host_port}
success_extra=ℹ️ S3：127.0.0.1:${s3_port}
success_extra=🔐 S3 accessKey：${user_name}
success_extra=🔐 S3 secretKey：${pass_word}
success_extra=📄 S3 設定檔：${instance_dir}/s3.json
success_extra=bucket_name：${bucket_name}（對應 filer 路徑 /buckets/${bucket_name}）
success_warn=若要對外請搭配 Nginx 反向代理（HTTPS），並在 security.toml 添加域名。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=master|template=quadlet/default.container|suffix=-master.container
unit=volume|template=quadlet/default2.container|suffix=-volume.container
unit=filer|template=quadlet/default3.container|suffix=-filer.container
unit=s3|template=quadlet/default4.container|suffix=-s3.container
unit=postgres|template=quadlet/default5.container|suffix=-postgres.container

update_pull_images=docker.io/library/postgres:16-alpine
