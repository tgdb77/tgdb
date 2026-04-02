spec_version=1
display_name=Podman Exporter
image=quay.io/navidys/prometheus-podman-exporter:latest
doc_url=https://github.com/containers/prometheus-podman-exporter
menu_order=115

hidden=1
access_policy=local_only

base_port=9882

require_podman_socket=1

success_extra=ℹ️ 要讓Prometheus 可讀需修改 prometheus.yml 加上 target：ip:9882
success_warn= 若要從別台機器抓取，建議用 Tailscale 內網訪問，或在防火牆只放行 Prometheus 來源 IP。

quadlet_type=single
quadlet_template=quadlet/default.container

