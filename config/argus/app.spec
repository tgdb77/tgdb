spec_version=1
display_name=Argus
image=docker.io/releaseargus/argus:latest
doc_url=https://github.com/release-argus/Argus
menu_order=78

access_policy=local_only

base_port=8880

instance_subdirs=etc data
record_subdirs=etc data

cli_quick_args=user_name pass_word

input=user_name|prompt=請輸入 Argus 帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=ARGUS_WEB_BASIC_AUTH_USERNAME|allow_cancel=1
input=pass_word|prompt=請輸入 Argus 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=ARGUS_WEB_BASIC_AUTH_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=etc/config.yml|template=configs/config.yml.example|mode=600|label=config.yml（Argus 設定）

success_extra=🔐 Basic Auth 帳號：${user_name}
success_extra=🔐 Basic Auth 密碼：${pass_word}
success_extra=🧩 要添加監測清單：請使用編輯單元功能調整config.yml

quadlet_type=single
quadlet_template=quadlet/default.container
