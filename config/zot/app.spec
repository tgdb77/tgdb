spec_version=1
display_name=Zot
image=ghcr.io/project-zot/zot:v2.1.15
doc_url=https://zotregistry.dev/
menu_order=77

base_port=5288

access_policy=local_only

instance_subdirs=etc registry
record_subdirs=etc registry

cli_quick_args=user_name pass_word

input=user_name|prompt=請輸入 Zot 帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=ZOT_USER|allow_cancel=1
input=pass_word|prompt=請輸入 Zot 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=ZOT_PASSWORD|allow_cancel=1

config=etc/htpasswd|template=configs/htpasswd.example|mode=600|label=htpasswd（Zot 登入）
config=etc/config.yml|template=configs/config.yml.example|mode=600|label=config.yml（Zot 設定）

pre_deploy=scripts/pre_deploy_init_htpasswd.sh|runner=bash|allow_fail=0

success_extra=🔐 Zot 帳號：${user_name}
success_extra=🔐 Zot 密碼：${pass_word}
success_extra=🛠️ 需調整registries.conf（HTTP 範例）：[[registry]] location="127.0.0.1:${host_port}" insecure=true
success_warn= 請勿直接對外公開；若需公開，請先完成反向代理/HTTPS，並視需求調整 ${instance_dir}/etc/config.yml 的 TLS、授權規則與 externalUrl。
success_warn= 若啟用 CVE 掃描（Trivy DB），需要對外網路、足夠磁碟與 /tmp 空間。

quadlet_type=single
quadlet_template=quadlet/default.container
