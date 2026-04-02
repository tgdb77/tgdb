spec_version=1
display_name=Grafana
image=docker.io/grafana/grafana:latest
doc_url=https://github.com/grafana/grafana
menu_order=110

hidden=1
access_policy=local_only

base_port=3993
instance_subdirs=data data/logs data/plugins
record_subdirs=data

cli_quick_args=admin_user admin_pass

input=admin_user|prompt=請輸入 Grafana 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|no_space=1|default=admin|env=GRAFANA_ADMIN_USER|allow_cancel=1
input=admin_pass|prompt=請輸入 Grafana 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=GRAFANA_ADMIN_PASSWORD|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 Grafana 管理員帳號：${admin_user}
success_extra=🔐 Grafana 管理員密碼：${admin_pass}
success_warn= 若選擇反代到域名，請編輯 ${instance_dir}/.env 設定ROOT_URL 與 DOMAIN，並重啟單元。

quadlet_type=multi

unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
