spec_version=1
display_name=Blackbox Exporter
image=quay.io/prometheus/blackbox-exporter:latest
doc_url=https://github.com/prometheus/blackbox_exporter
menu_order=116

access_policy=local_only

base_port=9115

cli_quick_args=grafana_pod

input=grafana_pod|prompt=請輸入要加入的 Grafana Pod 名稱（預設 grafana；若你改名/遠端安裝請自行修改，輸入 0 取消）: |required=1|ask=1|no_space=1|default=grafana|env=BLACKBOX_EXPORTER_GRAFANA_POD|allow_cancel=1

config=blackbox.yml|template=configs/blackbox.yml.example|mode=600|label=blackbox.yml（Blackbox 設定）
edit_files=blackbox.yml

success_extra=ℹ️ 要讓Prometheus 可讀需修改 prometheus.yml 啟用監測。
success_warn=若你要使用 ICMP（ping）探測，容器可能需要 CAP_NET_RAW；請自行編輯 ${container_name}.container 加入 AddCapability=CAP_NET_RAW。

quadlet_type=single
quadlet_template=quadlet/default.container
