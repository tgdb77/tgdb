spec_version=1
display_name=Node Exporter
image=docker.io/prom/node-exporter:latest
doc_url=https://github.com/prometheus/node_exporter
menu_order=112

hidden=1
access_policy=local_only

base_port=9100

success_extra=ℹ️ 要讓Prometheus 可讀需修改 prometheus.yml 加上 target：ip:9100
success_warn= 若要從別台機器抓取，建議用 Tailscale 內網訪問，或在防火牆只放行 Prometheus 來源 IP。
success_warn= node_exporter 不提供登入/密碼；不建議直接反向代理到公網。若你仍要對外提供，請務必加上防火牆白名單與認證。

quadlet_type=single
quadlet_template=quadlet/default.container
