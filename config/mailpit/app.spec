spec_version=1
display_name=Mailpit
image=docker.io/axllent/mailpit:latest
doc_url=https://mailpit.axllent.org/docs/
menu_order=107

base_port=8025
access_policy=local_only

instance_subdirs=data
record_subdirs=data

cli_quick_args=smtp_port
input=smtp_port|prompt=請輸入 SMTP 對外埠（預設 1025；輸入 0 取消）: |required=1|ask=1|type=port|default_source=next_available_port|start=1025|avoid=host_port|check_available=1|allow_cancel=1|cli_zero_as_default=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=📨 SMTP（寄信主機）：127.0.0.1:${smtp_port}
success_extra=🔌 API：${http_url}/api/v1
success_warn=Mailpit 預設用途為開發與測試郵件，生產環境需使用可靠的身分認證。

quadlet_type=single
quadlet_template=quadlet/default.container
