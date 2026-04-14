spec_version=1
display_name=EMQX
image=docker.io/emqx/emqx:latest
doc_url=https://docs.emqx.com/en/emqx/latest/deploy/install-docker.html
menu_order=146

access_policy=local_only

base_port=28083
instance_subdirs=data log
record_subdirs=data log

cli_quick_args=mqtt_port dashboard_password
input=mqtt_port|prompt=請輸入 MQTT 對外埠（預設 2883，輸入 0 取消）: |required=1|ask=1|type=port|default=2883|check_available=1|avoid=host_port|env=EMQX_MQTT_PORT|allow_cancel=1|cli_zero_as_default=1
input=dashboard_password|prompt=請輸入 EMQX Dashboard 管理密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|ask=1|type=password|no_space=1|default_source=strong_password|len=24|env=EMQX_DASHBOARD__DEFAULT_PASSWORD|allow_cancel=1|cli_zero_as_default=1

var=emqx_node_cookie|source=random_hex|len=32|env=EMQX_NODE__COOKIE

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 Dashboard 帳號：admin
success_extra=🔐 Dashboard 密碼：${dashboard_password}
success_extra=📡 MQTT TCP：127.0.0.1:${mqtt_port}
success_warn= 本範本預設僅綁定 127.0.0.1；如需讓其他節點連入 MQTT，請到「Headscale → Tailnet 服務埠轉發」新增 TCP/${mqtt_port}，或自行調整 Quadlet 綁定 IP。
success_warn= 安全提醒：EMQX 預設未啟用驗證器；若要對外開放 MQTT，請先在 Dashboard 設定 Authentication / Authorization，再評估是否開放 18083 / 18084 / 18883 等額外協定埠。

quadlet_type=single
quadlet_template=quadlet/default.container
