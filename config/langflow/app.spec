spec_version=1
display_name=Langflow
image=docker.io/langflowai/langflow:latest
doc_url=https://github.com/langflow-ai/langflow
menu_order=66

base_port=7866
instance_subdirs=langflow
record_subdirs=langflow

input=superuser|prompt=請輸入 Langflow 超級管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|env=LANGFLOW_SUPERUSER|allow_cancel=1
input=superuser_password|prompt=請輸入 Langflow 超級管理員密碼（直接按 Enter 使用隨機密碼）: |type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=LANGFLOW_SUPERUSER_PASSWORD
var=secret_key|source=random_hex|len=64|env=LANGFLOW_SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 超級管理員帳號：${superuser}
success_extra=🔐 超級管理員密碼：${superuser_password}
success_warn=安全預設已關閉 auto-login；若日後要公開對外提供，請持續保留 LANGFLOW_AUTO_LOGIN=False，並搭配反向代理 / HTTPS。
success_warn=版本提醒：若你之後改成固定 image tag，官方文件建議避開 1.6.0～1.6.3 與 1.7.0。

quadlet_type=single
quadlet_template=quadlet/default.container
