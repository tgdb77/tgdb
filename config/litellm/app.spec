spec_version=1
display_name=LiteLLM
image=docker.litellm.ai/berriai/litellm:main-stable
doc_url=https://docs.litellm.ai/docs/proxy/deploy
menu_order=135

base_port=4884

instance_subdirs=pgdata
record_subdirs=pgdata

cli_quick_args=db_user db_pass
input=db_user|prompt=請輸入 LiteLLM PostgreSQL 帳號（預設 litellm，輸入 0 取消）: |required=1|ask=1|no_space=1|default=litellm|env=LITELLM_DB_USER|allow_cancel=1
input=db_pass|prompt=請輸入 LiteLLM PostgreSQL 密碼（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=LITELLM_DB_PASSWORD|allow_cancel=1

var=master_key|source=random_hex|len=48|prefix=sk-|env=LITELLM_MASTER_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config.yaml|template=configs/config.yaml.example|mode=600|label=config.yaml

success_extra=🖥️ 管理面板：${http_url}/ui
success_extra=🔐 LiteLLM MASTER_KEY：${master_key}
success_extra=🔐 PostgreSQL 帳號：${db_user}
success_extra=🔐 PostgreSQL 密碼：${db_pass}
success_extra=📝 請編輯 ${instance_dir}/config.yaml 設定模型清單與上游提供者參數。
success_warn= 管理面板與 Proxy 會共用上述 MASTER_KEY；請妥善保存 ${instance_dir}/.env，避免外洩。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=main|template=quadlet/default.container|suffix=.container
unit=postgres|template=quadlet/default2.container|suffix=-postgres.container

update_pull_images=docker.io/postgres:16-alpine
