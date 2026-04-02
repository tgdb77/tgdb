spec_version=1
display_name=Prometheus
image=docker.io/prom/prometheus:latest
doc_url=https://github.com/prometheus/prometheus
menu_order=111

hidden=1
access_policy=local_only

base_port=9099
instance_subdirs=data
record_subdirs=data

cli_quick_args=grafana_pod

input=grafana_pod|prompt=請輸入要加入的 Grafana Pod 名稱（預設 grafana；若你改名/遠端安裝請自行修改，輸入 0 取消）: |required=1|ask=1|no_space=1|default=grafana|env=PROMETHEUS_GRAFANA_POD|allow_cancel=1

touch_files=prometheus.yml
config=prometheus.yml|template=configs/prometheus.yml.example|mode=600|label=prometheus.yml（Prometheus 設定）

edit_files=prometheus.yml

success_warn=Prometheus 預設不會對外開放埠（因為 Port Publish 需在 Pod 設定）。若你需要 Prometheus Web UI，請編輯 Grafana 的 .pod 單元自行加入 PublishPort。
success_warn=Grafana 要新增 Prometheus 資料來源時，URL 建議填 http://localhost:9090（同一個 Pod 內走 localhost），或根據部屬方式調整。

quadlet_type=single
quadlet_template=quadlet/default.container

