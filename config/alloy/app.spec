spec_version=1
display_name=Grafana Alloy
image=docker.io/grafana/alloy:latest
doc_url=https://github.com/grafana/alloy
menu_order=114

access_policy=local_only

base_port=12345
instance_subdirs=data
record_subdirs=data

deploy_mode_default=rootful
compat_deploy_modes=rootful

input=node_instance|prompt=請輸入此節點在 Prometheus 顯示的名稱（預設 hostname；輸入 0 取消）: |required=1|ask=1|no_space=1|default_source=hostname|pattern=^[A-Za-z0-9_.:-]+$|pattern_msg=節點名稱僅允許英數與 . _ : -|env=ALLOY_NODE_INSTANCE|allow_cancel=1
input=prom_host|prompt=請輸入 Prometheus 位址（輸入 0 取消）: |required=1|ask=1|no_space=1|default=host.containers.internal:9090|pattern=^[A-Za-z0-9_.:-]+$|pattern_msg=僅允許 hostname/IP（可含 :port；不要輸入 http(s):// 或路徑）|env=ALLOY_PROM_HOST|allow_cancel=1
input=loki_host|prompt=請輸入 Loki 位址（輸入 0 取消）: |required=1|ask=1|no_space=1|default=host.containers.internal:3100|pattern=^[A-Za-z0-9_.:-]+$|pattern_msg=僅允許 hostname/IP（可含 :port；不要輸入 http(s):// 或路徑）|env=ALLOY_LOKI_HOST|allow_cancel=1

config=alloy.config|template=configs/alloy.example.config|mode=600|label=alloy.config（Alloy 設定）
edit_files=alloy.config

success_extra=🔗 Alloy Metrics：${http_url}/metrics
success_warn= 本範本預設會收集宿主機日誌（/var/log + journald）並送到 Loki（http://${loki_host}/loki/api/v1/push）；請確認你理解資料外洩風險，且 Loki/Alloy 不要直接曝露到公網。
success_warn= 本範本也會收集宿主機指標（node_exporter 類指標）並 remote_write 到 Prometheus（http://${prom_host}/api/v1/write）， Loki/Prometheus 端點需對 Alloy 可達（例如同機用 host.containers.internal，或綁定內網/Tailscale IP）。

quadlet_type=single
quadlet_template=quadlet/default.container
