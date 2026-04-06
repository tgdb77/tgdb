spec_version=1
display_name=Alertmanager
image=docker.io/prom/alertmanager:latest
doc_url=https://github.com/prometheus/alertmanager
menu_order=117

access_policy=local_only

base_port=9093
instance_subdirs=data
record_subdirs=data

cli_quick_args=grafana_pod

input=grafana_pod|prompt=請輸入要加入的 Grafana Pod 名稱（預設 grafana；若你改名/遠端安裝請自行修改，輸入 0 取消）: |required=1|ask=1|no_space=1|default=grafana|env=ALERTMANAGER_GRAFANA_POD|allow_cancel=1

config=alertmanager.yml|template=configs/alertmanager.yml.example|mode=600|label=alertmanager.yml（Alertmanager 設定）
edit_files=alertmanager.yml

success_warn=Alertmanager 預設沒有登入/驗證；不建議直接對外開放 9093。若需要跨主機存取，請用 Tailscale/防火牆白名單等方式保護。
success_warn=你仍需自行在 Prometheus 設定檔加入 alerting.alertmanagers，並設定告警規則（rule_files）才會送出告警。

quadlet_type=single
quadlet_template=quadlet/default.container
