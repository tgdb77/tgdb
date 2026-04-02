spec_version=1
display_name=Grafana Alloy
image=docker.io/grafana/alloy:latest
doc_url=https://github.com/grafana/alloy
menu_order=114

hidden=1
access_policy=local_only

base_port=12345
instance_subdirs=data
record_subdirs=data

cli_quick_args=grafana_pod

input=grafana_pod|prompt=請輸入要加入的 Grafana Pod 名稱（預設 grafana；若你改名/遠端安裝請自行修改，輸入 0 取消）: |required=1|ask=1|no_space=1|default=grafana|env=ALLOY_GRAFANA_POD|allow_cancel=1

config=config.alloy|template=configs/config.alloy.example|mode=600|label=config.alloy（Alloy 設定）
edit_files=config.alloy

success_extra=🔗 Alloy Metrics（同 Pod）：http://127.0.0.1:12345/metrics
success_warn= Alloy 預設不會對外開放 12345（在 Pod 設定）。若你需要跨主機存取，請編輯設定檔與 Grafana 的 .pod 單元自行加入 PublishPort，並搭配防火牆/驗證保護。
success_warn= 本範本預設會收集宿主機日誌（/var/log + journald）並送到同 pod 的 Loki；請確認你理解資料外洩風險，且 Loki/Alloy 不要直接曝露到公網。

quadlet_type=single
quadlet_template=quadlet/default.container
