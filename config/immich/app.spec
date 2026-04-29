spec_version=1
display_name=Immich
image=ghcr.io/immich-app/immich-server:v2.7.5
doc_url=https://immich.app/docs/
menu_order=8

base_port=3311
instance_subdirs=pgdata rdata
record_subdirs=pgdata rdata

uses_volume_dir=1
volume_dir_prompt=照片目錄

cli_quick_args=user_name pass_word volume_dir
input=user_name|prompt=請輸入 PostgreSQL 帳號（預設 immich，輸入 0 取消）: |required=1|no_space=1|ask=1|default=immich|env=IMMICH_DB_USER|allow_cancel=1
input=pass_word|prompt=請輸入 PostgreSQL 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|env=IMMICH_DB_PASSWORD|allow_cancel=1

var=jwt_secret|source=random_hex|len=64|env=IMMICH_JWT_SECRET

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

success_extra=🔐 PostgreSQL 帳號：${user_name}
success_extra=🔐 PostgreSQL 密碼：${pass_word}
success_extra=🔐 Redis 密碼：${pass_word}

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container
unit=redis|template=quadlet/default3.container|suffix=-redis.container

update_pull_images=ghcr.io/immich-app/immich-server:release
update_pull_images=ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
update_pull_images=docker.io/redis:7-alpine
